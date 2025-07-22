/*
Copyright 2024 The HAMi Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package scheduler

import (
	"context"
	"encoding/json"
	"net/http"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"k8s.io/klog/v2"
	logf "sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/webhook/admission"

	"github.com/Project-HAMi/HAMi/pkg/device"
	"github.com/Project-HAMi/HAMi/pkg/scheduler/config"
)

const template = "Processing admission hook for pod %v/%v, UID: %v"

type webhook struct {
	decoder *admission.Decoder
}

// hasGPUResources checks if a container requests any GPU resources
func hasGPUResources(container *corev1.Container) bool {
	if container.Resources.Requests == nil && container.Resources.Limits == nil {
		return false
	}

	// Check both requests and limits for GPU resources
	for _, resources := range []corev1.ResourceList{container.Resources.Requests, container.Resources.Limits} {
		if resources == nil {
			continue
		}

		// Check for various GPU resource types
		gpuResourceNames := []string{
			"nvidia.com/gpu",
			"nvidia.com/gpucores",
			"nvidia.com/gpumem-percentage",
			"nvidia.com/gpumem",
			"amd.com/gpu",
			"intel.com/gpu",
		}

		for _, resourceName := range gpuResourceNames {
			if quantity, exists := resources[corev1.ResourceName(resourceName)]; exists {
				if !quantity.IsZero() {
					return true
				}
			}
		}
	}

	return false
}

// shouldInjectRuntimeClass determines if runtime class should be injected for this pod
func shouldInjectRuntimeClass(pod *corev1.Pod) bool {
	// Skip if runtime class injection is disabled
	if !config.EnableRuntimeClassInjection {
		return false
	}

	// Skip if pod already has a runtime class specified
	if pod.Spec.RuntimeClassName != nil && *pod.Spec.RuntimeClassName != "" {
		return false
	}

	// Skip if this is a privileged pod (likely system pod)
	for _, container := range pod.Spec.Containers {
		if container.SecurityContext != nil &&
			container.SecurityContext.Privileged != nil &&
			*container.SecurityContext.Privileged {
			return false
		}
	}

	// Check if any container requests GPU resources
	for _, container := range pod.Spec.Containers {
		if hasGPUResources(&container) {
			return true
		}
	}

	return false
}

// injectRuntimeClass adds the NVIDIA runtime class to the pod spec
func injectRuntimeClass(pod *corev1.Pod) {
	if config.RuntimeClassName != "" {
		pod.Spec.RuntimeClassName = &config.RuntimeClassName
		klog.Infof("Injected runtime class '%s' for GPU pod %s/%s",
			config.RuntimeClassName, pod.Namespace, pod.Name)
	}
}

func NewWebHook() (*admission.Webhook, error) {
	logf.SetLogger(klog.NewKlogr())
	schema := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(schema); err != nil {
		return nil, err
	}
	decoder := admission.NewDecoder(schema)
	wh := &admission.Webhook{Handler: &webhook{decoder: decoder}}
	return wh, nil
}

func (h *webhook) Handle(_ context.Context, req admission.Request) admission.Response {
	pod := &corev1.Pod{}
	err := h.decoder.Decode(req, pod)
	if err != nil {
		klog.Errorf("Failed to decode request: %v", err)
		return admission.Errored(http.StatusBadRequest, err)
	}
	if len(pod.Spec.Containers) == 0 {
		klog.Warningf(template+" - Denying admission as pod has no containers", req.Namespace, req.Name, req.UID)
		return admission.Denied("pod has no containers")
	}
	klog.Infof(template, req.Namespace, req.Name, req.UID)
	hasResource := false

	// Check if we should inject runtime class for GPU workloads
	if shouldInjectRuntimeClass(pod) {
		injectRuntimeClass(pod)
		klog.Infof(template+" - Injected runtime class for GPU pod", req.Namespace, req.Name, req.UID)
	}

	for idx, ctr := range pod.Spec.Containers {
		c := &pod.Spec.Containers[idx]
		if ctr.SecurityContext != nil {
			if ctr.SecurityContext.Privileged != nil && *ctr.SecurityContext.Privileged {
				klog.Warningf(template+" - Denying admission as container %s is privileged", req.Namespace, req.Name, req.UID, c.Name)
				continue
			}
		}
		for _, val := range device.GetDevices() {
			found, err := val.MutateAdmission(c, pod)
			if err != nil {
				klog.Errorf("validating pod failed:%s", err.Error())
				return admission.Errored(http.StatusInternalServerError, err)
			}
			hasResource = hasResource || found
		}
	}

	if !hasResource {
		klog.Infof(template+" - Allowing admission for pod: no resource found", req.Namespace, req.Name, req.UID)
		//return admission.Allowed("no resource found")
	} else if len(config.SchedulerName) > 0 {
		pod.Spec.SchedulerName = config.SchedulerName
		if pod.Spec.NodeName != "" {
			klog.Infof(template+" - Pod already has node assigned", req.Namespace, req.Name, req.UID)
			return admission.Denied("pod has node assigned")
		}
	}
	marshaledPod, err := json.Marshal(pod)
	if err != nil {
		klog.Errorf(template+" - Failed to marshal pod, error: %v", req.Namespace, req.Name, req.UID, err)
		return admission.Errored(http.StatusInternalServerError, err)
	}
	return admission.PatchResponseFromRaw(req.Object.Raw, marshaledPod)
}
