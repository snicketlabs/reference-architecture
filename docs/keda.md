<!---
title: Event Driven Autoscaling (KEDA)
folder: "Technical Documentation"
status: 2
-->

# Event Driven Autoscaling (KEDA)

[KEDA](https://keda.sh/) (Kubernetes Event-driven Autoscaling) provides the event-driven autoscaling used by the Match ingest pipeline.

KEDA is installed by default as part of the reference architecture to enable autoscaling capabilities for the Match environment.

If you prefer to install KEDA through other methods (or manage it separately), you can disable the automated installation:

-  set the `install_helm_charts` variable to `false`.


The application enables KEDA scaling via the Helm chart's `kedaAutoScaling.enabled` value.
