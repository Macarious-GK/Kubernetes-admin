App archetectures 
- Monolethic single big unit
- SOA service orianted archeterue using APIS
- Microservices: each service has its own codebase and team acting as indebended working entity







# ----------------------------------------------------------------General
## Kubernetes General
### labels and seclectors
kubectl get pods -l key=value
kubectl get pods -l 'key in (value, value), key notin (value, value)'
kubectl get pods --show-labels

we use labels to easyly identify app and pods so somethiong like service can find the target pods with matchlabels selectors

each resource in k8s has its metadata/labels that can identfy with 

### Secrets & Configmap
- ConfigMap:
    - A ConfigMap is a Kubernetes API object used to store non-confidential configuration data in key-value pairs.
    - let you store configuration for other objects using **Key/value pairs** & inject them to *running pods*
    - Provide configuration files to apps
- Secrets:
    - stores sensitive data
    - Types:
        - opaque: default
        - serviceAccount Token: 
        - Basic Authentication: contian two key/value pairs creds 
        - SSH, TLS: private key, certs
- Usage:
    - 
    - Using Configmaps as environment variables
- When a ConfigMap currently consumed in a volume is updated, projected keys are eventually updated as well.
- ConfigMaps consumed as environment variables are not updated automatically and require a pod restart.
- Files inside the volume are updated, but Pods won't re-read unless app watches file changes
#### Commands
- kubectl get cm name -o yaml
- kubectl describe cm name
- kubectl create cm name --from-file=path/to/file
- kubectl create cm name --from-literal=env=test
---
- kubectl create secret type name --from-file=path/to/file
- kubectl create secret type name --from-literal=env=test



# ----------------------------------------------------------------Networking
## Kubernetes Networking
### Service
 
#### Types:
- Cluster IP: service only accesable within the k8s cluster, not exposed outside the cluster
- NodePort: service accesable on static port defined, can be accessed from outside the cluster
- LoadBalancer: service accessable through cloud provider load balancer
- ExternalName: service as a way to return an alias to external services ouside the cluster 
#### commands:
- kubectl expose deploy ndeploy --name=nservice --type=ClusterIP --port= --target-port= 
- kubectl port-forward svc/nservice port:port
- sudo socat TCP-LISTEN:exposed_port,fork TCP:127.0.0.1:internal_port
- minikube service svc/nservice 



### Ingress: 
minikube addons enable ingress

- act as entrypoint to the cluster and can route you to multiple services 
- you can access k8s services from outside of the cluster by defining inbound rules
- It combined from API, controller and Rules (APIs implemented by controller "can act as loadbalancer")
- 
#### Hostname & Path
- by default it accecpt all http requests without defining matching hostname but when it defined it will match first with hostname and route the trafic to the target service
- Path types: 
    - ImplementationSpecific: With this path type, matching is up to the IngressClass.
    - Exact: "/bar" exact path
    - Prefix: "/" all pathes 
- Types of Ingress:
    - ingress backed with one service
    - Simple fanout: one entry point to multiple services based on URL provided
    - Name based virtual hosting: single ip address to multipe service based on hostname

### Gateway:
#### Resource model
- GatewayClass: Defines a set of gateways with common configuration 
- Gateway: Defines an instance of traffic handling infrastructure,
- HTTPRoute / TCPRoute / GRPCRoute: Defines specific rules for mapping traffic and how traffic is routed to services based on the host, path, or protocols.
- we install gateway CRDs and we install gatewayclass controller 
- we use gateway to have more control over calls from outside of the k8s
- we can't use backend ref to another namespace without using ReferenceGrant for **(enable cross namespace references )**
- This security mesusers made to overcome *CVE-2021-25740: Endpoint & EndpointSlice permissions allow cross-Namespace forwarding*
- We use **ReferenceGrant** and describe *From* and *To* to enable cross-ns, to make our httproute able to access and forward traffic to our service in another ns
- Gateway API is used for North/South traffic ***out/in**cluster* 
#### commands:
- kubectl describe gatewayclass nginx
- kubectl describe gateway gateway-name
- kubectl describe httproute httproute-name
- kubectl describe refercegrant

#### Links here: 
- https://docs.nginx.com/nginx-gateway-fabric/installation/installing-ngf/manifests/
- https://blog.nashtechglobal.com/hands-on-kubernetes-gateway-api-with-nginx-gateway-fabric/ 
- https://gateway-api.sigs.k8s.io/api-types/referencegrant/
- https://www.manifests.io/gateway%20api/1.1.0%20standard/io.k8s.networking.gateway.v1alpha2.ReferenceGrant 


### Network Policy

# ----------------------------------------------------------------Storage
## Kubernetes Storage

- Kubernetes applications (pods) are ephemeral by default (if a pod is deleted or crashes, its data is lost.) --> Not **presistent**

- Kubernetes support something called Dynamic Provisioninig for storage 
    - Using PVC to auto Create and assign space for the asked storage by pvc

- 


### Volume
- Used for Data persistence and Shared storage.
- Usage: 
    - specify the volumes to provide for the Pod in .spec.volumes and declare where to mount those volumes into containers in .spec.containers[*].volumeMounts.

### Storage Class
- **StorageClass** is a way to describe different types of storage available in your Kubernetes cluster.
    - `provisioner`: Specifies the storage provider.
    - `parameters`:
    - `reclaimPolicy`: Defines what happens when the PersistentVolumeClaim (PVC) is deleted (Retain,Delete)
    - `allowVolumeExpansion`: Allows expanding the size of the persistent volume.
- A StorageClass in Kubernetes can be set to manual to disable dynamic provisioning, meaning Kubernetes won’t automatically create volumes for you. Instead, you’ll have to manually create PersistentVolumes (PVs).
- Local storage, on the other hand, refers to disks physically attached to the nodes. While Kubernetes doesn’t automatically provision local storage by default,### PersistentVolume 

### PersistentVolume
- **A PersistentVolume (PV)** is the actual storage resource that Kubernetes manages. It is a physical storage resource that has been allocated in the cluster.
    - `Source`: Cloud storage, Network File System (NFS), Host-based storage (hostpath)
    - `Capacity`: 1Gi, 5Gi
    - `AccessModes`: 
        - ReadWriteOnce (RWO): Can only be mounted by a single node.
        - ReadOnlyMany (ROX): Can be mounted by multiple nodes in read-only mode.
        - ReadWriteMany (RWX): Can be mounted by multiple nodes in read-write mode.
    - `ReclaimPolicy`: When a PVC is deleted, defines whether the PV should be deleted, retained, or recycled.
    
### PersistentVolumeClaim 
- **A PersistentVolumeClaim (PVC)** is a request for storage by a user (or a pod).
    - `Requesting storage`:
    - `Access modes`:
    - `storageClassName`: Specifies which StorageClass to use

#### How the PVC and PV Are Linked
- These two resources will successfully `bind` because:
    - storage size
    - accessModes
    - storageClassName

- For sharing volume with replicas we need to achieve **ReadWriteMany (RWX) shared volumes**
- `Dynamic Provisioning` in Kubernetes refers to the automatic creation of PersistentVolumes (PVs) by Kubernetes when a PersistentVolumeClaim (PVC) is created, based on the StorageClass specified in the PVC.

- https://hbayraktar.medium.com/how-to-setup-dynamic-nfs-provisioning-in-a-kubernetes-cluster-cbf433b7de29
- https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner

# ----------------------------------------------------------------State
## Kubernetes stateless vs stateful 

### Deployment  (stateless)
- A stateless application does not store any data between sessions. Each request is independent — the app doesn’t care what happened before.
#### Commands
kubectl scale deploy ndeploy --replicas=3
kubectl set image deploy ndeploy continer_name=newImage
kubectl rollout status deployment/ndeploy
kubectl rollout history deployment/ndeploy
kubectl rollout undo deployment/ndeploy     #Rollback

#### Deployment strategies
- Rolling Update Deployment (Default)
    - This strategy replace pod by pod without any downtime 
    - Minor performance reduction happened (the desired no. of pods is less by one)
- Recreate Deployment
    - This strategy shutdown all old pods and up the new ones 
    - Used for system that cannot work with partially update state 
    - It has downtime
- Canary Deployment
    - Its partially update strategy that allow you to test your new version by assigning % of the real users to user the new version 25%

#### Multi Container Pods
 more than one conatinaer in one pod
- Design Patterns:
    - SideCar: Main app container and Helper Container
    - Ambassador: connect the containers with outside world (Act as Proxy)
    - Adaptor: It adapte the requests in/out 
- Communictatoin:
    - Shared network Namespace (localhost)
    - Shared Volumn
    - Shard Process

### StatefulSets (stateful)
- A StatefulSet runs a group of Pods, and maintains a sticky identity for each of those Pods. This is useful for managing applications that need persistent storage or a stable, unique network identity.
- A stateful application needs to remember things — it stores data that must persist across restarts.

- StatefulSets are valuable for applications that require one or more of the following.
    - Stable, unique network identifiers.
    - Stable, persistent storage.
    - Ordered, graceful deployment and scaling.
    - Ordered, automated rolling updates.
- StatefulSets currently require a Headless Service to be responsible for the network identity of the Pods. 
- The volumeClaimTemplates will provide stable storage using PersistentVolumes provisioned by a PersistentVolume Provisioner
- 
#### 