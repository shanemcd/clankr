# KubeVirt Container Disk Images

Container disk images are OCI container images with a qcow2 file at `/disk/`. KubeVirt mounts them as `containerDisk` volumes for VMs. This doc covers two approaches we tried.

## Approach 1: virt-customize (what works today)

Starts from a Fedora Cloud base qcow2 (which has cloud-init pre-configured) and uses `virt-customize` to inject packages and the `openshell-sandbox` binary. Runs as an OpenShift BuildConfig on CRC.

### Setup

```bash
export KUBECONFIG=~/.crc/machines/crc/kubeconfig

oc new-project openshell-sandboxes
oc create imagestream openshell-sandbox-kubevirt -n openshell-sandboxes

oc apply -n openshell-sandboxes -f - << 'EOF'
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: openshell-sandbox-kubevirt
spec:
  output:
    to:
      kind: ImageStreamTag
      name: openshell-sandbox-kubevirt:latest
  source:
    binary: {}
    type: Binary
  strategy:
    dockerStrategy:
      env:
        - name: BUILDAH_FORMAT
          value: docker
    type: Docker
  resources:
    limits:
      memory: 8Gi
    requests:
      memory: 4Gi
EOF
```

### Minimal image (SSH + supervisor only)

`Dockerfile.kubevirt-minimal`:

```dockerfile
FROM registry.fedoraproject.org/fedora:44 AS builder
RUN dnf install -y libguestfs-tools-c qemu-img guestfs-tools curl && dnf clean all
RUN curl -L -o /tmp/fedora-cloud.qcow2 \
    "https://download.fedoraproject.org/pub/fedora/linux/releases/42/Cloud/x86_64/images/Fedora-Cloud-Base-Generic-42-1.1.x86_64.qcow2"
COPY openshell-sandbox /tmp/openshell-sandbox
RUN export LIBGUESTFS_BACKEND=direct && \
    qemu-img resize /tmp/fedora-cloud.qcow2 10G && \
    virt-customize -a /tmp/fedora-cloud.qcow2 \
        --install cloud-init,cloud-utils-growpart,openssh-server,openssh-clients,iproute,nftables \
        --mkdir /opt/openshell/bin \
        --mkdir /etc/openshell \
        --mkdir /etc/openshell-tls/client \
        --mkdir /sandbox \
        --upload /tmp/openshell-sandbox:/opt/openshell/bin/openshell-sandbox \
        --chmod 0755:/opt/openshell/bin/openshell-sandbox \
        --link /opt/openshell/bin/openshell-sandbox:/openshell-sandbox \
        --run-command 'groupadd -g 10001 sandbox || true' \
        --run-command 'useradd -u 10001 -g 10001 -m -d /sandbox -s /bin/bash sandbox || true' \
        --run-command 'chown 10001:10001 /sandbox' \
        --run-command 'ssh-keygen -A' \
        --run-command 'systemctl enable sshd' \
        --selinux-relabel
FROM scratch
COPY --from=builder /tmp/fedora-cloud.qcow2 /disk/fedora.qcow2
```

### Building

```bash
BUILDDIR=$(mktemp -d)
cp /path/to/openshell-sandbox "$BUILDDIR/"
cp Dockerfile.kubevirt-minimal "$BUILDDIR/Dockerfile"

oc start-build openshell-sandbox-kubevirt \
  --from-dir="$BUILDDIR" \
  -n openshell-sandboxes \
  --follow

rm -rf "$BUILDDIR"
```

Takes ~4 minutes. The image is available at:
```
image-registry.openshift-image-registry.svc:5000/openshell-sandboxes/openshell-sandbox-kubevirt:latest
```

### Full image (with Hermes + ddgs)

The full `Dockerfile.kubevirt-disk` path is legacy. Prefer **bootc** (`Containerfile.kubevirt`) which layers NemoClaw Hermes + OpenShell supervisor + ddgs only (no rust/CLI toolchain).

### Limitations

- No layer caching. Every rebuild runs all `virt-customize` steps from scratch.
- Slow (~4 min for minimal, ~10+ min for full).
- Disk space constrained in CRC build pods.
- The Fedora Cloud 42 base image is used because Fedora 44 Cloud images weren't available at time of testing. The tools installed inside (from Fedora 42 repos) may have older versions than the host.

## Approach 2: bootc + bootc-image-builder (better but needs rootful podman)

Write a standard Containerfile using `quay.io/fedora/fedora-bootc:44` as the base, layer NemoClaw Hermes + OpenShell supervisor + ddgs (fast, cached layers), then convert the container image to a qcow2 with `bootc-image-builder`.

### Prerequisites: NemoClaw Hermes base

Build from [`shanemcd/NemoClaw` `kubevirt-sidecar`](https://github.com/shanemcd/NemoClaw/tree/kubevirt-sidecar) (includes `nemoclaw-start-vm` / `NEMOCLAW_VM_SIDECAR=1`). Do **not** use `nemoclaw-hermes-configured` (that layer adds rust/CLIs for the pod path).

```bash
# From agents/hermes/openshell/
./build-nemoclaw-hermes-kubevirt.sh
# → localhost/nemoclaw-hermes:kubevirt
```

Also copy a release `openshell-sandbox` binary built from [`shanemcd/OpenShell` `kubevirt-sidecar`](https://github.com/shanemcd/OpenShell/tree/kubevirt-sidecar) into this directory before the bootc build.

### The Containerfile

`Containerfile.kubevirt` multi-stage:

1. `FROM localhost/nemoclaw-hermes:kubevirt AS nemoclaw`
2. `FROM quay.io/fedora/fedora-bootc:44` — COPY supervisor + Hermes/NemoClaw bits, install **ddgs** only, Slack-only config overlay, NemoClaw posture.

No rustup, no gcc/clang/cmake, no gh/glab/gws/oc/jirahhh, no in-image sed/python patches.

### Building the container image

```bash
podman build -f Containerfile.kubevirt -t localhost/hermes-sandbox-kubevirt:latest .
```

This is fast (~2 min with cache) and uses standard container layer caching.

### Converting to qcow2

`bootc-image-builder` converts the bootc container image to a qcow2. It requires rootful podman.

#### On the host (needs rootful podman)

```bash
sudo podman run --rm --privileged \
  --security-opt label=type:unconfined_t \
  -v ./output:/output \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  quay.io/centos-bootc/bootc-image-builder:latest \
  --type qcow2 --rootfs ext4 \
  localhost/hermes-sandbox-kubevirt:latest
```

On Fedora Atomic (Silverblue/Kinoite) without sudo, this doesn't work. Rootless podman with `--root` is detected and rejected.

#### On CRC (what worked)

Push the bootc image to the CRC internal registry, then run `bootc-image-builder` as a privileged pod:

```bash
# Push bootc image to CRC registry
REGISTRY=default-route-openshift-image-registry.apps-crc.testing
podman tag localhost/hermes-sandbox-kubevirt:latest "$REGISTRY/openshell-sandboxes/hermes-sandbox-bootc:latest"
podman push --tls-verify=false "$REGISTRY/openshell-sandboxes/hermes-sandbox-bootc:latest"

# Grant pull permissions
oc policy add-role-to-user system:image-puller \
  system:serviceaccount:openshell-sandboxes:default -n openshell-sandboxes

# Run bootc-image-builder as a pod with init container to pull the image
oc apply -n openshell-sandboxes -f - << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: bootc-builder
spec:
  restartPolicy: Never
  initContainers:
  - name: pull-image
    image: quay.io/podman/stable:latest
    command:
    - sh
    - -c
    - |
      mkdir -p /var/lib/containers/storage/overlay
      TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
      podman pull --tls-verify=false --creds="serviceaccount:${TOKEN}" \
        image-registry.openshift-image-registry.svc:5000/openshell-sandboxes/hermes-sandbox-bootc:latest
    securityContext:
      privileged: true
      runAsUser: 0
    volumeMounts:
    - name: container-storage
      mountPath: /var/lib/containers/storage
  containers:
  - name: builder
    image: quay.io/centos-bootc/bootc-image-builder:latest
    args:
    - --type
    - qcow2
    - --rootfs
    - ext4
    - image-registry.openshift-image-registry.svc:5000/openshell-sandboxes/hermes-sandbox-bootc:latest
    securityContext:
      privileged: true
      runAsUser: 0
    resources:
      requests:
        memory: 4Gi
      limits:
        memory: 8Gi
    volumeMounts:
    - name: output
      mountPath: /output
    - name: store
      mountPath: /store
    - name: container-storage
      mountPath: /var/lib/containers/storage
  volumes:
  - name: output
    persistentVolumeClaim:
      claimName: bootc-output
  - name: store
    emptyDir:
      sizeLimit: 30Gi
  - name: container-storage
    emptyDir:
      sizeLimit: 30Gi
EOF
```

After the build completes, the qcow2 is on the PVC. Package it as a container disk:

```bash
oc apply -n openshell-sandboxes -f - << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: disk-packager
spec:
  restartPolicy: Never
  containers:
  - name: packager
    image: quay.io/podman/stable:latest
    command:
    - sh
    - -c
    - |
      set -ex
      QCOW2=$(find /output -name "*.qcow2" | head -1)
      mkdir -p /tmp/build/disk
      cp "$QCOW2" /tmp/build/disk/fedora.qcow2
      printf 'FROM scratch\nCOPY disk/fedora.qcow2 /disk/fedora.qcow2\n' > /tmp/build/Containerfile
      cd /tmp/build
      podman build -t image-registry.openshift-image-registry.svc:5000/openshell-sandboxes/openshell-sandbox-kubevirt:latest .
      TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
      podman push --tls-verify=false --creds="serviceaccount:${TOKEN}" \
        image-registry.openshift-image-registry.svc:5000/openshell-sandboxes/openshell-sandbox-kubevirt:latest
    securityContext:
      privileged: true
      runAsUser: 0
    volumeMounts:
    - name: output
      mountPath: /output
  volumes:
  - name: output
    persistentVolumeClaim:
      claimName: bootc-output
EOF
```

Grant push permissions first:
```bash
oc policy add-role-to-user system:image-builder \
  system:serviceaccount:openshell-sandboxes:default -n openshell-sandboxes
```

### Gotchas

- The init container needs `system:image-puller` RBAC to pull from the internal registry.
- The packager pod needs `system:image-builder` RBAC to push.
- `bootc-image-builder` needs `/var/lib/containers/storage/overlay` to exist (the init container creates it).
- The bootc-built qcow2 had SSH issues: `sshd` was enabled but cloud-init's `NoCloud` datasource wasn't properly configured, so cloud-init didn't run. The virt-customize approach uses a Fedora Cloud base that has cloud-init pre-configured.
- SELinux on CRC: the builder pod needs `privileged: true` and `runAsUser: 0`.

## Which approach to use

| Concern | virt-customize | bootc |
|---------|---------------|-------|
| Build speed | Slow (no caching) | Fast (layer caching) |
| Cloud-init | Works (Fedora Cloud base has it) | Needs manual datasource config |
| Rootful podman | Not needed (runs on CRC) | Required for bootc-image-builder |
| Disk space | Constrained in CRC build pods | Same issue |
| Iterability | Poor (full rebuild every time) | Good (incremental layers) |

For now, use **virt-customize** for the minimal image (reliable cloud-init) and invest in fixing the **bootc** approach for the full Hermes image (better caching, faster iteration).
