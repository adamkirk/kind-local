# Init kube-prometheus

See installation instructions here: https://github.com/prometheus-operator/kube-prometheus

```
$ docker run -it --rm -v "$(pwd):/srv" -w /srv quay.io/coreos/jsonnet-ci bash
$ jb init
$ jb install github.com/prometheus-operator/kube-prometheus/jsonnet/kube-prometheus@main
```