{{/*
Expand the name of the chart.
*/}}
{{- define "mongodb-vm.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
mongodb-vm.val — resolve a value that may arrive either as a proper nested path
(e.g. .Values.ha.enabled) or as a flat dot-notation top-level key
(e.g. index .Values "ha.enabled") when the broker passes overrides via helm.valuesObject.

Usage: {{ include "mongodb-vm.val" (list . "ha.enabled") }}

The nested path is always preferred; the flat key is the fallback.
This handles the BYOP broker helm-registry path which serialises overrides as
{"ha.enabled": true, "diskImage.sourceContainerDisk": "..."} — flat string keys,
not nested objects — inside helm.valuesObject.
*/}}
{{- define "mongodb-vm.val" -}}
{{- $ctx    := index . 0 -}}
{{- $dotKey := index . 1 -}}
{{- /* Flat top-level key takes priority (broker passes overrides as flat keys
       e.g. "ha.enabled", "diskImage.storageClassName").
       Only fall back to nested path walk when no flat key exists. */ -}}
{{- $flatVal := index $ctx.Values $dotKey -}}
{{- if not (kindIs "invalid" $flatVal) -}}
  {{- $flatVal -}}
{{- else -}}
  {{- /* Walk the nested path */ -}}
  {{- $parts  := splitList "." $dotKey -}}
  {{- $cur    := $ctx.Values -}}
  {{- $found  := true -}}
  {{- range $parts -}}
    {{- if $found -}}
      {{- $next := index $cur . -}}
      {{- if kindIs "invalid" $next -}}
        {{- $found = false -}}
      {{- else -}}
        {{- $cur = $next -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
  {{- if and $found (not (kindIs "invalid" $cur)) -}}
    {{- $cur -}}
  {{- end -}}
{{- end -}}
{{- end }}

{{/*
Create a default fully qualified app name (base, without member index).
*/}}
{{- define "mongodb-vm.fullname" -}}
{{- /* Broker passes instanceName as a flat key; chart values use instance.name nested. */ -}}
{{- $name := index .Values "instanceName" | default .Values.instance.name -}}
{{- if $name }}
{{- $name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Per-member VM name  — called with a dict: (dict "Values" .Values "Chart" .Chart "Release" .Release "index" $i)
Standalone:  <fullname>
HA member:   <fullname>-<index>   e.g. my-instance-0
*/}}
{{- define "mongodb-vm.memberName" -}}
{{- $base := include "mongodb-vm.fullname" . -}}
{{- if include "mongodb-vm.val" (list . "ha.enabled") | eq "true" -}}
{{- printf "%s-%d" $base (int .index) | trunc 63 | trimSuffix "-" }}
{{- else -}}
{{- $base }}
{{- end }}
{{- end }}

{{/*
Per-member DataVolume name.
Standalone:  <fullname>-disk
HA member:   <fullname>-<index>-disk
*/}}
{{- define "mongodb-vm.memberDvName" -}}
{{- $base := include "mongodb-vm.fullname" . -}}
{{- if include "mongodb-vm.val" (list . "ha.enabled") | eq "true" -}}
{{- printf "%s-%d-disk" $base (int .index) | trunc 63 | trimSuffix "-" }}
{{- else -}}
{{- printf "%s-disk" $base }}
{{- end }}
{{- end }}

{{/*
DataVolume name — legacy helper kept for backward compatibility (standalone path).
*/}}
{{- define "mongodb-vm.dvName" -}}
{{ include "mongodb-vm.fullname" . }}-disk
{{- end }}

{{/*
Headless service name (HA only) — used as the DNS domain for replica-set member discovery.
Members are reachable at <memberName>.<headlessSvcName>.<namespace>.svc.cluster.local
*/}}
{{- define "mongodb-vm.headlessSvcName" -}}
{{- printf "%s-headless" (include "mongodb-vm.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
VIP service name (HA + vip.enabled only) — primary-only LoadBalancer or NodePort Service.
*/}}
{{- define "mongodb-vm.vipSvcName" -}}
{{- printf "%s-vip" (include "mongodb-vm.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "mongodb-vm.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mongodb-vm.name" . }}
app.kubernetes.io/instance: {{ include "mongodb-vm.fullname" . }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "mongodb-vm.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ include "mongodb-vm.name" . }}
app.kubernetes.io/instance: {{ include "mongodb-vm.fullname" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "mongodb-vm.annotations" -}}
{{- with .Values.commonAnnotations }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
DataVolume spec — source + storage block, shared by standalone and HA branches.
Accepts the root context (.) directly.
*/}}
{{- define "mongodb-vm.dvSpec" -}}
{{- /*
  Resolve disk image source. Values may arrive either as a proper nested structure
  (diskImage.sourceContainerDisk) or as flat dot-notation top-level keys
  ("diskImage.sourceContainerDisk") when the broker passes overrides via
  helm.valuesObject. The index function handles the flat-key fallback.
*/ -}}
{{- $containerDisk := index .Values "diskImage.sourceContainerDisk" | default .Values.diskImage.sourceContainerDisk }}
{{- $sourceURL     := index .Values "diskImage.sourceURL"            | default .Values.diskImage.sourceURL }}
{{- $sourcePVC     := index .Values "diskImage.sourcePVCName"        | default .Values.diskImage.sourcePVCName }}
{{- $pullSecret    := index .Values "diskImage.pullSecret"           | default .Values.diskImage.pullSecret }}
{{- $certConfigMap := index .Values "diskImage.certConfigMap"        | default .Values.diskImage.certConfigMap }}
{{- $sourcePVCNS   := index .Values "diskImage.sourcePVCNamespace"   | default .Values.diskImage.sourcePVCNamespace }}
{{- $storageClass  := index .Values "diskImage.storageClassName"     | default .Values.diskImage.storageClassName }}
{{- $diskSizeGi    := index .Values "diskImage.diskSizeGi"           | default .Values.diskImage.diskSizeGi }}
{{- if $containerDisk }}
source:
  registry:
    url: "docker://{{ $containerDisk }}"
    {{- if $pullSecret }}
    secretRef: {{ $pullSecret | quote }}
    {{- end }}
    {{- if $certConfigMap }}
    certConfigMap: {{ $certConfigMap | quote }}
    {{- end }}
{{- else if $sourceURL }}
source:
  http:
    url: {{ $sourceURL | quote }}
{{- else if $sourcePVC }}
source:
  pvc:
    name: {{ $sourcePVC | quote }}
    namespace: {{ $sourcePVCNS | default .Release.Namespace | quote }}
{{- else }}
{{- fail "One of diskImage.sourceContainerDisk, diskImage.sourceURL, or diskImage.sourcePVCName must be set" }}
{{- end }}
storage:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: {{ $diskSizeGi }}Gi
  storageClassName: {{ $storageClass | quote }}
  volumeMode: Block
{{- end }}


{{/*
Resolve the three instance passwords — lookup existing Secret first (upgrade path),
otherwise generate fresh random passwords (first-deploy path).
This is called by both credentials-secret.yaml and the cloud-init userdata so that
all three templates use the exact same password values in a single Helm render.
Passwords are NEVER read from values.yaml.
Returns a JSON dict: vmPass / rootPass / dbPass.
*/}}
{{- define "mongodb-vm.resolvePasswords" -}}
{{- $ns         := .Values.namespaceOverride | default .Release.Namespace -}}
{{- $secretName := printf "%s-mongodb-creds" (include "mongodb-vm.fullname" .) -}}
{{- $existing   := lookup "v1" "Secret" $ns $secretName -}}
{{- $vmPass     := "" -}}
{{- $rootPass   := "" -}}
{{- $dbPass     := "" -}}
{{- $vmPassHash := "" -}}
{{- if $existing -}}
  {{- $vmPass     = index $existing.data "vm_root_password"      | b64dec -}}
  {{- $rootPass   = index $existing.data "root_password"         | b64dec -}}
  {{- $dbPass     = index $existing.data "database_password"     | b64dec -}}
  {{- $vmPassHash = index $existing.data "vm_root_password_hash" | b64dec -}}
  {{- /* Upgrade path: Secret exists but hash key missing — generate once and it will be persisted on next apply */ -}}
  {{- if not $vmPassHash -}}
    {{- $vmPassHash = $vmPass | bcrypt -}}
  {{- end -}}
{{- else -}}
  {{- $vmPass     = randAlphaNum 24 -}}
  {{- $rootPass   = randAlphaNum 24 -}}
  {{- $dbPass     = randAlphaNum 24 -}}
  {{- $vmPassHash = $vmPass | bcrypt -}}
{{- end -}}
{{- dict "vmPass" $vmPass "rootPass" $rootPass "dbPass" $dbPass "vmPassHash" $vmPassHash | toJson -}}
{{- end }}

{{/*
Name of the per-instance Concert SSH keypair Secret. Defaults to <instance>-concert-ssh so
every deployment gets its own key, owned by (and deleted with) that deployment.
Override with concertSSHKeySecret only to share one key deliberately.
Needs .Values and .Chart in the calling context.
*/}}
{{- define "mongodb-vm.concertSecretName" -}}
{{- .Values.concertSSHKeySecret | default (printf "%s-concert-ssh" (include "mongodb-vm.fullname" .)) -}}
{{- end }}

{{/*
<name>-mongodb-creds Secret. Called from cloudinit-secret.yaml with the SAME resolved
passwords that go into the VM cloud-init, so the Secret always matches the VMs.
Call: include "mongodb-vm.credsSecret" (dict "root" $ "p" $passwords)

Retrieve after deployment:
  kubectl get secret <name>-mongodb-creds -n <ns> -o jsonpath='{.data.vm_root_password}' | base64 -d
  kubectl get secret <name>-mongodb-creds -n <ns> -o jsonpath='{.data.root_password}' | base64 -d
  kubectl get secret <name>-mongodb-creds -n <ns> -o jsonpath='{.data.database_password}' | base64 -d
*/}}
{{- define "mongodb-vm.credsSecret" -}}
{{- $r := .root -}}
{{- $p := .p }}
---
apiVersion: v1
kind: Secret
metadata:
  name: {{ printf "%s-mongodb-creds" (include "mongodb-vm.fullname" $r) }}
  namespace: {{ $r.Values.namespaceOverride | default $r.Release.Namespace }}
  labels:
    {{- include "mongodb-vm.labels" $r | nindent 4 }}
  annotations:
    {{- include "mongodb-vm.annotations" $r | nindent 4 }}
    sovcore.byop.ibm.com/secret-type: mongodb-credentials
    sovcore.byop.ibm.com/instance: {{ include "mongodb-vm.fullname" $r | quote }}
type: Opaque
data:
  vm_root_password: {{ $p.vmPass | b64enc | quote }}
  ## bcrypt hash of vm_root_password — the same hash cloud-init chpasswd uses.
  vm_root_password_hash: {{ $p.vmPassHash | b64enc | quote }}
  ## MongoDB admin username — always "root" (created by mongo-first-boot.sh step 4).
  root_username: {{ "root" | b64enc | quote }}
  root_password: {{ $p.rootPass | b64enc | quote }}
  database_password: {{ $p.dbPass | b64enc | quote }}
  database_user: {{ (include "mongodb-vm.val" (list $r "mongodb.databaseUser") | default "appuser") | b64enc | quote }}
  database_name: {{ (include "mongodb-vm.val" (list $r "mongodb.databaseName") | default "appdb") | b64enc | quote }}
{{- end }}

{{/*
Cloud-init userdata — standalone (no replica set).
*/}}
{{- define "mongodb-vm.userdata" -}}
{{- /* sharedPasswords is passed by cloudinit-secret.yaml so the VM and the creds Secret agree */ -}}
{{- $p          := .sharedPasswords -}}
{{- if not $p -}}
{{- $p = include "mongodb-vm.resolvePasswords" . | fromJson -}}
{{- end -}}
{{- $vmPass     := $p.vmPass -}}
{{- $rootPass   := $p.rootPass -}}
{{- $dbPass     := $p.dbPass -}}
{{- $vmPassHash := $p.vmPassHash -}}
{{- /* Merge Concert cluster SSH key (from Secret) with any user-supplied keys */ -}}
{{- $allSSHKeys := .Values.sshAuthorizedKeys | default list -}}
{{- $concertSecretName := include "mongodb-vm.concertSecretName" . -}}
{{- $ns := .Values.namespaceOverride | default .Release.Namespace -}}
{{- $concertSecret := lookup "v1" "Secret" $ns $concertSecretName -}}
{{- if $concertSecret -}}
  {{- $concertKey := index $concertSecret.data "authorized_key" | b64dec -}}
  {{- if $concertKey -}}
    {{- $allSSHKeys = append $allSSHKeys $concertKey -}}
  {{- end -}}
{{- end -}}
#cloud-config
disable_root: false
{{- /* 'default' marks cloud-user (system_info.default_user) as the default user: cloud-init
     gives the datasource public-keys (the Concert key delivered by KubeVirt accessCredentials)
     ONLY to the default user. Without it they were silently dropped. */}}
users:
  - default
  - name: root
    lock_passwd: false
{{- if $allSSHKeys }}
    ssh_authorized_keys:
      {{- range $allSSHKeys }}
      - {{ . | quote }}
      {{- end }}
{{- end }}
  - name: cloud-user
    lock_passwd: false
    groups: wheel
    sudo: ALL=(ALL) NOPASSWD:ALL
    passwd: {{ $vmPassHash | quote }}
{{- if $allSSHKeys }}
    ssh_authorized_keys:
      {{- range $allSSHKeys }}
      - {{ . | quote }}
      {{- end }}
{{- end }}
chpasswd:
  list: |
    root:{{ $vmPass }}
    cloud-user:{{ $vmPass }}
  expire: false
## ssh_pwauth: false — SSH is key-only (mdb-virt-01 / iscf-ia-04). The Concert public key
## reaches authorized_keys via KubeVirt accessCredentials (see virtualmachine.yaml).
## Console login with the chpasswd password is unaffected (it is not SSH).
ssh_pwauth: false
write_files:
  - path: /etc/mongo-init-env
    permissions: '0600'
    content: |
      DB_NAME={{ .Values.mongodb.databaseName }}
      DB_USER={{ .Values.mongodb.databaseUser }}
      DB_PASS={{ $dbPass }}
      ADMIN_PASS={{ $rootPass }}

  - path: /etc/mongo-compliance-env
    permissions: '0600'
    content: |
      ## Phase 2 compliance flags — sourced by mongo-first-boot.sh
      ## mdb-enc-02 (iscf-cr-01/dr-06): WiredTiger encryption-at-rest
      MONGO_COMPLIANCE_ENCRYPTION={{ include "mongodb-vm.val" (list . "compliance.enableEncryption") | default "false" | lower }}
      ## mdb-aud-01 (iscf-ia-04/gov-03/dr-10) + mdb-aud-02 (iscf-ia-04/gov-02/ai-04)
      MONGO_COMPLIANCE_AUDIT={{ include "mongodb-vm.val" (list . "compliance.auditLog.enabled") | default "false" | lower }}
      MONGO_COMPLIANCE_AUDIT_PATH={{ include "mongodb-vm.val" (list . "compliance.auditLog.path") | default "/var/log/mongodb/audit.json" }}
      MONGO_COMPLIANCE_AUDIT_AUTH_SUCCESS={{ include "mongodb-vm.val" (list . "compliance.auditLog.auditAuthorizationSuccess") | default "true" | lower }}

  - path: /etc/mongo-rsyslog-env
    permissions: '0600'
    content: |
      ## rsyslog injection flags — sourced by mongo-first-boot.sh
      MONGO_RSYSLOG_ENABLED={{ include "mongodb-vm.val" (list . "logging.rsyslog.enabled") | default "false" | lower }}
      MONGO_RSYSLOG_FWD_ENABLED={{ include "mongodb-vm.val" (list . "logging.rsyslog.forwarding.enabled") | default "false" | lower }}
      MONGO_RSYSLOG_FWD_HOST={{ include "mongodb-vm.val" (list . "logging.rsyslog.forwarding.host") | default "" | quote }}
      MONGO_RSYSLOG_FWD_PORT={{ include "mongodb-vm.val" (list . "logging.rsyslog.forwarding.port") | default "514" }}
      MONGO_RSYSLOG_FWD_PROTOCOL={{ include "mongodb-vm.val" (list . "logging.rsyslog.forwarding.protocol") | default "tcp" | quote }}
      MONGO_RSYSLOG_FWD_FORMAT={{ include "mongodb-vm.val" (list . "logging.rsyslog.forwarding.format") | default "rfc5424" | quote }}
      MONGO_RSYSLOG_MONGOD_ENABLED={{ include "mongodb-vm.val" (list . "logging.rsyslog.fileMonitoring.mongodLog.enabled") | default "true" | lower }}
      MONGO_RSYSLOG_MONGOD_TAG={{ include "mongodb-vm.val" (list . "logging.rsyslog.fileMonitoring.mongodLog.tag") | default "mongodb-mongod" | quote }}
      MONGO_RSYSLOG_MONGOD_FACILITY={{ include "mongodb-vm.val" (list . "logging.rsyslog.fileMonitoring.mongodLog.facility") | default "local6" | quote }}
      MONGO_RSYSLOG_MONGOD_SEVERITY={{ include "mongodb-vm.val" (list . "logging.rsyslog.fileMonitoring.mongodLog.severity") | default "info" | quote }}
      MONGO_RSYSLOG_AUDIT_ENABLED={{ include "mongodb-vm.val" (list . "logging.rsyslog.fileMonitoring.auditLog.enabled") | default "false" | lower }}
      MONGO_RSYSLOG_AUDIT_PATH={{ include "mongodb-vm.val" (list . "logging.rsyslog.fileMonitoring.auditLog.path") | default "/var/log/mongodb/audit.json" | quote }}
      MONGO_RSYSLOG_AUDIT_TAG={{ include "mongodb-vm.val" (list . "logging.rsyslog.fileMonitoring.auditLog.tag") | default "mongodb-audit" | quote }}
      MONGO_RSYSLOG_AUDIT_FACILITY={{ include "mongodb-vm.val" (list . "logging.rsyslog.fileMonitoring.auditLog.facility") | default "local7" | quote }}
      MONGO_RSYSLOG_AUDIT_SEVERITY={{ include "mongodb-vm.val" (list . "logging.rsyslog.fileMonitoring.auditLog.severity") | default "notice" | quote }}
      MONGO_RSYSLOG_RATELIMIT_INTERVAL={{ include "mongodb-vm.val" (list . "logging.rsyslog.rateLimit.intervalSeconds") | default "5" }}
      MONGO_RSYSLOG_RATELIMIT_BURST={{ include "mongodb-vm.val" (list . "logging.rsyslog.rateLimit.burstCount") | default "500" }}
  {{- $rsyslogCustom := include "mongodb-vm.val" (list . "logging.rsyslog.customConf") }}
  {{- if $rsyslogCustom }}
  ## Verbatim rsyslog snippet — written as-is to the drop-in path.
  ## mongo-first-boot.sh appends this to /etc/rsyslog.d/60-mongodb.conf.
  - path: /etc/mongo-rsyslog-custom.conf
    content: |
      {{ $rsyslogCustom | nindent 6 }}
    permissions: '0640'
  {{- end }}
  {{- $ntpServer := include "mongodb-vm.val" (list . "ntp.server") }}
  {{- if $ntpServer }}
  ## mdb-vm-01 (iscf-mi-03): site-specific NTP server (chrony drop-in)
  - path: /etc/chrony.d/site-ntp.conf
    permissions: '0644'
    content: |
      server {{ $ntpServer }} iburst
  {{- end }}
runcmd:
  {{- if $ntpServer }}
  - systemctl restart chronyd || true
  {{- end }}
  - set -a && . /etc/mongo-init-env && set +a && /usr/local/bin/mongo-first-boot.sh
{{- end }}

{{/*
Cloud-init userdata — HA replica-set member.
Called with a dict: (dict "Values" .Values "Chart" .Chart "Release" .Release "index" $i)

Every member:
  - writes /etc/mongo-init-env (credentials + replica-set config)
  - calls /usr/local/bin/mongo-first-boot.sh (must handle RS mode via MONGO_RS_* env vars)

Member-0 additionally:
  - calls /usr/local/bin/mongo-rs-init.sh which runs rs.initiate() with all member hosts
*/}}
{{- define "mongodb-vm.userdata.ha" -}}
{{- $base    := include "mongodb-vm.fullname" . -}}
{{- $svc     := include "mongodb-vm.headlessSvcName" . -}}
{{- $ns      := .Values.namespaceOverride | default .Release.Namespace -}}
{{- $rsName  := include "mongodb-vm.val" (list . "ha.replicaSetName") -}}
{{- $port    := include "mongodb-vm.val" (list . "ha.port") | default "27017" | int -}}
{{- $count   := include "mongodb-vm.val" (list . "ha.replicaCount") | default "3" | int -}}
{{- $idx     := int .index -}}
{{- $selfHost := printf "%s-%d.%s.%s.svc.cluster.local" $base $idx $svc $ns -}}
{{- /* Build the full member host list for rs.initiate() on member-0 */ -}}
{{- $members := list -}}
{{- range $i := until $count -}}
{{- $host := printf "%s-%d.%s.%s.svc.cluster.local:%d" $base $i $svc $ns $port -}}
{{- $members = append $members $host -}}
{{- end -}}
{{- $memberList := join "," $members -}}
{{- /*
  keyFile and passwords are generated ONCE in virtualmachine.yaml before the range loop
  and passed in via the dict as "sharedKeyFile" and "sharedPasswords" — all members
  share the same values. This fixes the ArgoCD lookup bug where resolvePasswords called
  inside the loop generates different randAlphaNum passwords per member.
*/ -}}
{{- $keyFile := .sharedKeyFile -}}
{{- /* Use sharedPasswords if passed in (HA path via virtualmachine.yaml range loop).
       Fall back to resolvePasswords for standalone path or direct template calls. */ -}}
{{- $p := .sharedPasswords -}}
{{- if not $p -}}
{{- $p = include "mongodb-vm.resolvePasswords" . | fromJson -}}
{{- end -}}
{{- $vmPass     := $p.vmPass -}}
{{- $rootPass   := $p.rootPass -}}
{{- $dbPass     := $p.dbPass -}}
{{- $vmPassHash := $p.vmPassHash -}}
{{- /* Merge Concert cluster SSH key (from Secret) with any user-supplied keys */ -}}
{{- $allSSHKeys := .Values.sshAuthorizedKeys | default list -}}
{{- $concertSecretName := include "mongodb-vm.concertSecretName" . -}}
{{- $concertNs := .Values.namespaceOverride | default .Release.Namespace -}}
{{- $concertSecret := lookup "v1" "Secret" $concertNs $concertSecretName -}}
{{- if $concertSecret -}}
  {{- $concertKey := index $concertSecret.data "authorized_key" | b64dec -}}
  {{- if $concertKey -}}
    {{- $allSSHKeys = append $allSSHKeys $concertKey -}}
  {{- end -}}
{{- end -}}
#cloud-config
disable_root: false
{{- /* 'default' marks cloud-user (system_info.default_user) as the default user: cloud-init
     gives the datasource public-keys (the Concert key delivered by KubeVirt accessCredentials)
     ONLY to the default user. Without it they were silently dropped. */}}
users:
  - default
  - name: root
    lock_passwd: false
{{- if $allSSHKeys }}
    ssh_authorized_keys:
      {{- range $allSSHKeys }}
      - {{ . | quote }}
      {{- end }}
{{- end }}
  - name: cloud-user
    lock_passwd: false
    groups: wheel
    sudo: ALL=(ALL) NOPASSWD:ALL
    passwd: {{ $vmPassHash | quote }}
{{- if $allSSHKeys }}
    ssh_authorized_keys:
      {{- range $allSSHKeys }}
      - {{ . | quote }}
      {{- end }}
{{- end }}
chpasswd:
  list: |
    root:{{ $vmPass }}
    cloud-user:{{ $vmPass }}
  expire: false
## ssh_pwauth: false — SSH is key-only (mdb-virt-01 / iscf-ia-04). The Concert public key
## reaches authorized_keys via KubeVirt accessCredentials (see virtualmachine.yaml).
## Console login with the chpasswd password is unaffected (it is not SSH).
ssh_pwauth: false
write_files:
  - path: /etc/mongo-init-env
    permissions: '0600'
    content: |
      DB_NAME={{ .Values.mongodb.databaseName }}
      DB_USER={{ .Values.mongodb.databaseUser }}
      DB_PASS={{ $dbPass }}
      ADMIN_PASS={{ $rootPass }}
      MONGO_RS_ENABLED=true
      MONGO_RS_NAME={{ $rsName }}
      MONGO_RS_MEMBERS={{ $memberList }}
      MONGO_RS_SELF={{ $selfHost }}
      MONGO_RS_INDEX={{ $idx }}

  - path: /etc/mongodb-keyfile
    ## Plain text — no encoding. sharedKeyFile is randAlphaNum (alphanumeric),
    ## or b64dec of a Kubernetes Secret, or an explicit plain-text value.
    ## MongoDB keyFile must be 6–1024 printable chars written as-is to disk.
    ## Quoted to prevent YAML special characters from breaking cloud-init parsing.
    content: {{ $keyFile | quote }}
    permissions: '0400'
    owner: 'mongod:mongod'
  {{- if include "mongodb-vm.val" (list . "vip.enabled") | eq "true" }}
  - path: /etc/mongo-probe-pass
    ## Root password read by mongo-primary-probe.py at startup.
    ## Only this credential file is written at runtime; the probe script and
    ## systemd unit are baked into the bootc image (scripts/mongo-primary-probe.py
    ## and units/mongo-primary-probe.service) to avoid OSError(30) — /usr/local/bin
    ## is read-only in the OSTree-managed /usr tree and cloud-init write_files
    ## cannot write there; doing so aborts the entire write_files module.
    content: {{ $rootPass }}
    permissions: '0400'
    owner: 'root:root'
{{- end }}
  - path: /etc/mongo-compliance-env
    permissions: '0600'
    content: |
      ## Phase 2 compliance flags — sourced by mongo-first-boot.sh
      ## mdb-enc-02 (iscf-cr-01/dr-06): WiredTiger encryption-at-rest
      MONGO_COMPLIANCE_ENCRYPTION={{ include "mongodb-vm.val" (list . "compliance.enableEncryption") | default "false" | lower }}
      ## mdb-aud-01 (iscf-ia-04/gov-03/dr-10) + mdb-aud-02 (iscf-ia-04/gov-02/ai-04)
      MONGO_COMPLIANCE_AUDIT={{ include "mongodb-vm.val" (list . "compliance.auditLog.enabled") | default "false" | lower }}
      MONGO_COMPLIANCE_AUDIT_PATH={{ include "mongodb-vm.val" (list . "compliance.auditLog.path") | default "/var/log/mongodb/audit.json" }}
      MONGO_COMPLIANCE_AUDIT_AUTH_SUCCESS={{ include "mongodb-vm.val" (list . "compliance.auditLog.auditAuthorizationSuccess") | default "true" | lower }}

  - path: /etc/mongo-rsyslog-env
    permissions: '0600'
    content: |
      ## rsyslog injection flags — sourced by mongo-first-boot.sh
      MONGO_RSYSLOG_ENABLED={{ include "mongodb-vm.val" (list . "logging.rsyslog.enabled") | default "false" | lower }}
      MONGO_RSYSLOG_FWD_ENABLED={{ include "mongodb-vm.val" (list . "logging.rsyslog.forwarding.enabled") | default "false" | lower }}
      MONGO_RSYSLOG_FWD_HOST={{ include "mongodb-vm.val" (list . "logging.rsyslog.forwarding.host") | default "" | quote }}
      MONGO_RSYSLOG_FWD_PORT={{ include "mongodb-vm.val" (list . "logging.rsyslog.forwarding.port") | default "514" }}
      MONGO_RSYSLOG_FWD_PROTOCOL={{ include "mongodb-vm.val" (list . "logging.rsyslog.forwarding.protocol") | default "tcp" | quote }}
      MONGO_RSYSLOG_FWD_FORMAT={{ include "mongodb-vm.val" (list . "logging.rsyslog.forwarding.format") | default "rfc5424" | quote }}
      MONGO_RSYSLOG_MONGOD_ENABLED={{ include "mongodb-vm.val" (list . "logging.rsyslog.fileMonitoring.mongodLog.enabled") | default "true" | lower }}
      MONGO_RSYSLOG_MONGOD_TAG={{ include "mongodb-vm.val" (list . "logging.rsyslog.fileMonitoring.mongodLog.tag") | default "mongodb-mongod" | quote }}
      MONGO_RSYSLOG_MONGOD_FACILITY={{ include "mongodb-vm.val" (list . "logging.rsyslog.fileMonitoring.mongodLog.facility") | default "local6" | quote }}
      MONGO_RSYSLOG_MONGOD_SEVERITY={{ include "mongodb-vm.val" (list . "logging.rsyslog.fileMonitoring.mongodLog.severity") | default "info" | quote }}
      MONGO_RSYSLOG_AUDIT_ENABLED={{ include "mongodb-vm.val" (list . "logging.rsyslog.fileMonitoring.auditLog.enabled") | default "false" | lower }}
      MONGO_RSYSLOG_AUDIT_PATH={{ include "mongodb-vm.val" (list . "logging.rsyslog.fileMonitoring.auditLog.path") | default "/var/log/mongodb/audit.json" | quote }}
      MONGO_RSYSLOG_AUDIT_TAG={{ include "mongodb-vm.val" (list . "logging.rsyslog.fileMonitoring.auditLog.tag") | default "mongodb-audit" | quote }}
      MONGO_RSYSLOG_AUDIT_FACILITY={{ include "mongodb-vm.val" (list . "logging.rsyslog.fileMonitoring.auditLog.facility") | default "local7" | quote }}
      MONGO_RSYSLOG_AUDIT_SEVERITY={{ include "mongodb-vm.val" (list . "logging.rsyslog.fileMonitoring.auditLog.severity") | default "notice" | quote }}
      MONGO_RSYSLOG_RATELIMIT_INTERVAL={{ include "mongodb-vm.val" (list . "logging.rsyslog.rateLimit.intervalSeconds") | default "5" }}
      MONGO_RSYSLOG_RATELIMIT_BURST={{ include "mongodb-vm.val" (list . "logging.rsyslog.rateLimit.burstCount") | default "500" }}
  {{- $rsyslogCustom := include "mongodb-vm.val" (list . "logging.rsyslog.customConf") }}
  {{- if $rsyslogCustom }}
  - path: /etc/mongo-rsyslog-custom.conf
    content: |
      {{ $rsyslogCustom | nindent 6 }}
    permissions: '0640'
  {{- end }}
  {{- $ntpServer := include "mongodb-vm.val" (list . "ntp.server") }}
  {{- if $ntpServer }}
  ## mdb-vm-01 (iscf-mi-03): site-specific NTP server (chrony drop-in)
  - path: /etc/chrony.d/site-ntp.conf
    permissions: '0644'
    content: |
      server {{ $ntpServer }} iburst
  {{- end }}
runcmd:
  {{- if $ntpServer }}
  - systemctl restart chronyd || true
  {{- end }}
  ## Trigger first-boot via systemctl start — this detaches mongo-first-boot.sh from the
  ## cloud-init runcmd process group entirely. Running the script inline in runcmd means
  ## any cloud-init session timeout or disconnect kills the script mid-run.
  ## mongodb-first-boot.service is Type=oneshot — systemctl start blocks until it completes.
  ## first-boot (member-0) copies the RS bootstrap env to /etc/mongo-rs-init.env and starts
  ## mongo-rs-init.service, which retries until the RS has a PRIMARY and survives reboots.
  ## No plaintext /tmp copy of the credentials is made any more.
  - systemctl start mongodb-first-boot.service
{{- if include "mongodb-vm.val" (list . "vip.enabled") | eq "true" }}
  ## mongo-primary-probe.service is baked into the image.
  ## Use systemd-run --no-block to avoid deadlocking the runcmd shell:
  ## calling `systemctl start` on a simple service from within a cloud-init runcmd
  ## cgroup causes systemd to wait for the service to become active while the runcmd
  ## is still blocking the same transaction — resulting in a permanent hang.
  - systemd-run --unit=mongo-probe-launcher --no-block /bin/bash -c 'systemctl start mongo-primary-probe.service'
{{- end }}
{{- end }}
