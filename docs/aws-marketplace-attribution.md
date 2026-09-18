<!---
title: AWS Marketplace Attribution
folder: "Technical Documentation"
status: 2
-->

# AWS Marketplace attribution (AWS only)

**Enable this if you bought The Lab through AWS Marketplace.** Setting `aws_marketplace_product_code` tags resources `aws-apn-id = pc:<code>`, which AWS reads under [Partner Revenue Measurement](https://docs.aws.amazon.com/PRM/latest/aws-prm-onboarding-guide/resource-tagging.html) to attribute your AWS spend to the software vendor.

```hcl
aws_marketplace_product_code = "lqmsrnudbo3xempf2qjr2ffo"
```

Use the product code, not the `prod-...` Product ID — the variable validates this.

Leave it unset if this deployment did not come through AWS Marketplace. The variable defaults to empty because the same configuration is deployed outside Marketplace and on GCP, where the tag means nothing.
