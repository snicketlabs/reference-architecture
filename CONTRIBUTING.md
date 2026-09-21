# Contributing

**Most of this repository is generated.** The terraform, the READMEs and
everything under `docs/`, `environments/` and `initial-state/` are published
here from an internal repository by an automated sync. A change made directly
here to any of those paths is overwritten the next time that sync runs — it
does not reach the source, and the work is lost.

## Reporting a problem

Open an issue. That is the right route for anything you have found in the
reference architecture, and it reaches us.

## Proposing a change

Open an issue describing what you would change rather than a pull request.
A pull request against a generated path cannot be merged here; we make the
change upstream and it appears in the next sync.

## The helm charts

The `secrets-configuration-aws` and `secrets-configuration-gcp` charts are not
in this repository. They are published to
[ad-signalio/helm-charts](https://github.com/ad-signalio/helm-charts/tree/main/charts),
where you can read the templates and values.
