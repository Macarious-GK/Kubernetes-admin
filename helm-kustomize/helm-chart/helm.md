# HELM
- Act as package manager in Kubernetes
- Let us to treat our apps in kubernetes as apps instead of just collection of resources or objects 
- eliminate the micromanagement of each k8s object 
- `helm 3` has 3-way strategic merge patch: detect any changes and compare it to the last revision taken and to current working version to apply rollbacks
- Create Dynamic resources templates
- let you centralized the place of updating app dynamic values like version


## Helm Components
- cli --> Manage helm apps
- charts --> collection of apps and config of the app
- Release --> single installation of the app using helm chart 'release has names'
- Revision --> Snapshot of the app
- Metadata --> stored in secret in k8s cluster
- Repositories --> ArtifactHUB.io

### Helm Charts
- Chart Types:
    - application
    - library

- consist of three files 
    - templete files 
    - values.yaml
    - chart.yaml 
    - chart_dependences

#### Functions
- apply function to the values passed to templates
```yaml
{{ default "nginx".Values.image.repository }}     |           | nginx       # Normal Func
{{ upper "nginx".Values.image.repository }}       | nginx     | NGINX
{{ quote "nginx".Values.image.repository }}       | nginx     | "nginx"
{{ replace "0.2" "0.3" .Values.image.tag }}       | nginx:0.2 | nginx:0.3
{{ .Values.image.repository | default "nginx"}}   |           | nginx       # Func using Pipeline
```

#### Conditions
- apply conditions if a values will be presented on a condition "If existed"
- We can wrap all the resource in {{- if .Values.servcieaccount.create}} to make this resource created based on this condition  
```yaml
{{- if .Values.orglabel}}                # the '-' will remove the empty raw
Label:
    org: {{ .Values.orglabel}}
{{- else if eq .Values.orglabel "hr"}}   # add if the values equal to "hr" then apply this section
Label:
    org: Human Resources
{{- end}}
# create  a resource based on condition
{{- with .Values.serviceAccount.create }}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ $.Values.serviceAccount.name }}
  labels:
    app: webapp-color
{{- end }}
```
---
- we can make the scope of the values referenced in the file made on another rather than Root
```Yaml
{{- with .Values.app}}
app1: {{.ui.bg}}                 # insted of {{.Values.app.ui.bg}}
app2: {{.ui.fg}}                 # insted of {{.Values.app.ui.fg}}
app3: {{.db.bg}}                 # insted of {{.Values.app.db.bg}}
{{ $.Release.Name }}             # the '$' represend the root scope like '~' in shell   
{{- end}}
```
#### Loops
- loops make use to list a set of values 
```yaml
# range will define the scope of the value that it iterate over it not `root` or `$`
# making the '.' is the value in each iteration, we can apply func to modify the outcome    
{{- range .Values.ranges}}
- {{ . }}
{{- end}}
#
{{- range $key, $val := $.Values.serviceAccount.labels }}
{{ $key }}: {{ $val }}
{{- end }}
app: webapp-color
```
#### Templates "_helpers.tpl"
- when we use some values across many resource repeatedly we can templates in helpers to reduce redundancy
```yaml
# define in _helpers.tpl
{{- define "labels" }}
    app: nodejs
    mode: legacy
{{- end }}
# define in resorces files
{{- template "labels"}}
{{- template "labels" . }}                   # use '.' if accessing releace name 
{{- include "labels" . | indend 4}}          # use include insted of template to act as func and can use pipeline with it to add indentation as needed to fix indentation errors
```

#### Hooks
- we use hooks to apply some action before update or delete like taking a backup of Database 
- EX: pre/post-upgrade, pre/post-rollback, pre/post-install, pre/post-delete
- This action is using k8s resource kind `Job` to do some script EX: `backup.sh`
- we use annotation to make helm run this before applying the action like 'upgrade our app'
- In case we have multiple actions we define weight "-999" --> "999" 
- we also define an action to this Job after complete its work by fail or success using annotation
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ .Release.Name }}-nginx
  annotations:
    "helm.sh/hook": pre-upgrade
    "helm.sh/hook-weight": "5"
    "helm.sh/hook-delete-policy": hook-succeeded
spec:
  template:
    metadata:
      name: {{ .Release.Name }}-nginx
    spec:
      restartPolicy: Never
      containers:
        - name: pre-upgrade-backup-job
          image: "alpine"
          command: ["/bin/backup.sh"]
```

#### Packaging & Signing Charts
```bash
gpg --full-generate-key
helm package ./chart_dir
helm package --sign --key "MacariousGK" --keyring ~/.gnupg/secring.gpg ./Mac_Node_V25.5/
gpg --list-keys
gpg --export-secret-keys > ~/.gnupg/secring.gpg
gpg --export > ~/.gnupg/pubring.gpg
helm verify Mac_Node_V25.5-0.1.0.tgz
helm install --verify chart_name

gpg --export-secret-keys --armor MacariousGK > private-key-backup.asc
gpg --export --armor MacariousGK > public-key.asc
helm repo index my_charts_filse/ --url https://macarious.me/DevSecOps_Self_Intern/
helm repo add myrepo https://macarious.me/DevSecOps_Self_Intern/

```

## Command
``` bash
helm repo add repo_name chart_URL                                               # add repo to our local repos
helm pull repo_name/appname                                                     # install the app files 
helm pull --untar repo_name/appname                                             # install the app files and un tar 
helm install releace_name rebo/appname                                          # deploy app with default value
helm install --values custom_values.yaml releace_name rebo/appname              # deploy app with custom value
helm search repo/hub
helm upgread releace_name repo_name/appname --version 
helm rollback releace_name
helm uninstall releace_name
helm list releace_name                                                          # list releaces
helm history                                                                    # History of charts and releases
helm create chart_name                                                           # create chart
helm lint chart_name                                                            # search for errors in chart
helm template chart_name                                                        # review the created templates
helm template chart_name --debug                                                # to debug in case of errors
helm install release_name chart_name --dry-run                                  # catch error while creating k8s error
```
---
``` bash
# Install Helm
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
sudo apt-get install apt-transport-https --yes
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm
```



Refernece: https://www.youtube.com/watch?v=sNNy8bN7ve0