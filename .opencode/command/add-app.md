---
description: Add an application to the kubernetes cluster
agent: build
---

Add a new application to the kubernetes cluster.

The app is $ARGUMENTS

- You will first search the web for the latest version of the docker image. We don't use `latest` so we need to specify the latest version.
- You will create the following file structure:

󰝰 apps <- argo cd application files go here
├╴ freshrss.yml <- argo cd application file (see other examples in this repo)
󰝰 freshrss <- example application name, using kebab-case if multiple words
├╴󰝰 templates <- (optional) any files/crds that cannot be applied using the app-template
│ └╴ freshrss-env-external-secret.yml <- (optional) secrets that should be injected via 1password
└╴ values.yml <- app-template helm chart values

IMPORTANT: all yaml files must contain the yaml-language-server annotation at the top of the file based on their internal type. For example, for app-template values file, use something like this:

# yaml-language-server: $schema=https://raw.githubusercontent.com/bjw-s-labs/helm-charts/app-template-4.1.2/charts/other/app-template/values.schema.json

For ArgoCD applications use something like this:

# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/argoproj.io/application_v1alpha1.json

Look at other files in this repo to determine what it should be, don't guess and
if adding a new schema url that doesn't exist in this repo yet, verify that the
schema url is real by curling it.

Run `task validate` at the end to validate all yaml files conform with their specified schema
