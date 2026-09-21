<!---
title: Event Driven Autoscaling (KEDA)
folder: "Technical Documentation"
status: 2
-->

# Event Driven Autoscaling (KEDA)

[KEDA](https://keda.sh/) (Kubernetes Event-driven Autoscaling) provides the event-driven autoscaling used by the Snicket Labs ingest pipeline.

KEDA is installed by default as part of the reference architecture to enable autoscaling capabilities for the Snicket Labs system.

If you prefer to install KEDA through other methods (or manage it separately), you can disable the automated installation:

-  set the `install_helm_charts` variable to `false`.


The platform enables KEDA scaling via the helm chart's `kedaAutoScaling.enabled` value.
