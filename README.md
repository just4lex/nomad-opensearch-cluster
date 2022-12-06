# nomad-opensearch-cluster
# Usage
```
levant render -var-file=config.json -out=opensearch-cluster.hcl opensearch-cluster.tmpl.hcl
nomad deploy -addr=<addr> opensearch-cluster.tmpl
```
# Descriprion
Somewhen