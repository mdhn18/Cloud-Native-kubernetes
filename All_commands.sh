
#################################################################################################
#################################################################################################
#################################################################################################
##############	Section B: Kubernetes Installation and Configuration Fundamentals ###############
#################################################################################################
#################################################################################################


###############################################c
#### Packageinstallation-containers ###########
###############################################

#Setup 
#   1. 4 VMs Ubuntu 22.04, 1 control plane, 3 nodes.
#   2. Static IPs on individual VMs
#   3. /etc/hosts hosts file includes name to IP mappings for VMs
#   4. Swap is disabled
#   5. Take snapshots prior to installation, this way you can install 
#       and revert to snapshot if needed
#
ssh aen@c1-cp1


#0 - Disable swap, swapoff then edit your fstab removing any entry for swap partitions
#You can recover the space with fdisk. You may want to reboot to ensure your config is ok. 
sudo swapoff -a
vi /etc/fstab


###IMPORTANT####
#I will keep the code in the course downloads up to date with the latest method.
################


#0 - Install Packages 
#containerd prerequisites, and load two modules and configure them to load on boot
#https://kubernetes.io/docs/setup/production-environment/container-runtimes/
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF


# Apply sysctl params without reboot
sudo sysctl --system


#Install containerd...
sudo apt-get install -y containerd


#Create a containerd configuration file
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml


#Set the cgroup driver for containerd to systemd which is required for the kubelet.
#For more information on this config file see:
# https://github.com/containerd/cri/blob/master/docs/config.md and also
# https://github.com/containerd/containerd/blob/master/docs/ops.md

#At the end of this section, change SystemdCgroup = false to SystemdCgroup = true
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
        ...
          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
            SystemdCgroup = true

#You can use sed to swap in true
sudo sed -i 's/            SystemdCgroup = false/            SystemdCgroup = true/' /etc/containerd/config.toml


#Verify the change was made
grep 'SystemdCgroup = true' /etc/containerd/config.toml


#Restart containerd with the new configuration
sudo systemctl restart containerd




#Install Kubernetes packages - kubeadm, kubelet and kubectl
#Add k8s.io's apt repository gpg key, this will likely change for each version of kubernetes release. 
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
sudo curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg


#Add the Kubernetes apt repository
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list


#Update the package list and use apt-cache policy to inspect versions available in the repository
sudo apt-get update
apt-cache policy kubelet | head -n 20 


#Install the required packages, if needed we can request a specific version. 
#Use this version because in a later course we will upgrade the cluster to a newer version.
#Try to pick one version back because later in this series, we'll run an upgrade
VERSION=1.29.1-1.1
sudo apt-get install -y kubelet=$VERSION kubeadm=$VERSION kubectl=$VERSION 
sudo apt-mark hold kubelet kubeadm kubectl containerd


#To install the latest, omit the version parameters. I have tested all demos with the version above, if you use the latest it may impact other demos in this course and upcoming courses in the series
#sudo apt-get install kubelet kubeadm kubectl
#sudo apt-mark hold kubelet kubeadm kubectl containerd


#1 - systemd Units
#Check the status of our kubelet and our container runtime, containerd.
#The kubelet will enter a inactive (dead) state until a cluster is created or the node is joined to an existing cluster.
sudo systemctl status kubelet.service
sudo systemctl status containerd.service


####################################################
######## CreateControlPlaneNode-container ##########
####################################################


#0 - Creating a Cluster
# Log into our control plane node
ssh aen@c1-cp1


#Create our kubernetes cluster, specify a pod network range matching that in calico.yaml! 
#Only on the Control Plane Node, download the yaml files for the pod network.
wget https://raw.githubusercontent.com/projectcalico/calico/master/manifests/calico.yaml


#Look inside calico.yaml and find the setting for Pod Network IP address range CALICO_IPV4POOL_CIDR, 
#adjust if needed for your infrastructure to ensure that the Pod network IP
#range doesn't overlap with other networks in our infrastructure.
vi calico.yaml


#You can now just use kubeadm init to bootstrap the cluster
sudo kubeadm init --kubernetes-version v1.29.1


#remove the kubernetes-version parameter if you want to use the latest.
#sudo kubeadm init


#Before moving on review the output of the cluster creation process including the kubeadm init phases, 
#the admin.conf setup and the node join command


#Configure our account on the Control Plane Node to have admin access to the API server from a non-privileged account.
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config


#1 - Creating a Pod Network
#Deploy yaml file for your pod network.
kubectl apply -f calico.yaml


#Look for the all the system pods and calico pods to change to Running. 
#The DNS pod won't start (pending) until the Pod network is deployed and Running.
kubectl get pods --all-namespaces


#Gives you output over time, rather than repainting the screen on each iteration.
kubectl get pods --all-namespaces --watch


#All system pods should be Running
kubectl get pods --all-namespaces


#Get a list of our current nodes, just the Control Plane Node Node...should be Ready.
kubectl get nodes 




#2 - systemd Units...again!
#Check out the systemd unit...it's no longer inactive (dead)...its active(running) because it has static pods to start
#Remember the kubelet starts the static pods, and thus the control plane pods
sudo systemctl status kubelet.service 


#3 - Static Pod manifests
#Let's check out the static pod manifests on the Control Plane Node
ls /etc/kubernetes/manifests


#And look more closely at API server and etcd's manifest.
sudo more /etc/kubernetes/manifests/etcd.yaml
sudo more /etc/kubernetes/manifests/kube-apiserver.yaml


#Check out the directory where the kubeconfig files live for each of the control plane pods.
ls /etc/kubernetes


####################################################
############# CreatesNodes-containers ##############
####################################################


#For this demo ssh into c1-node1
ssh aen@c1-node1


#Disable swap, swapoff then edit your fstab removing any entry for swap partitions
#You can recover the space with fdisk. You may want to reboot to ensure your config is ok. 
swapoff -a
vi /etc/fstab


#0 - Joining Nodes to a Cluster

#Install a container runtime - containerd
#containerd prerequisites, and load two modules and configure them to load on boot
#https://kubernetes.io/docs/setup/production-environment/container-runtimes/
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply sysctl params without reboot
sudo sysctl --system


#Install containerd...
sudo apt-get install -y containerd


#Configure containerd
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml


#Set the cgroup driver for containerd to systemd which is required for the kubelet.
#For more information on this config file see:
# https://github.com/containerd/cri/blob/master/docs/config.md and also
# https://github.com/containerd/containerd/blob/master/docs/ops.md

#At the end of this section, change SystemdCgroup = false to SystemdCgroup = true
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
        ...
#          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
            SystemdCgroup = true

#You can use sed to swap in true
sudo sed -i 's/            SystemdCgroup = false/            SystemdCgroup = true/' /etc/containerd/config.toml


#Verify the change was made
grep 'SystemdCgroup = true' /etc/containerd/config.toml


#Restart containerd with the new configuration
sudo systemctl restart containerd



#Install Kubernetes packages - kubeadm, kubelet and kubectl
#Add Google's apt repository gpg key
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
sudo curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg


#Add the Kubernetes apt repository
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list


#Update the package list and use apt-cache policy to inspect versions available in the repository
sudo apt-get update
apt-cache policy kubelet | head -n 20 


#Install the required packages, if needed we can request a specific version. 
#Use this version because in a later course we will upgrade the cluster to a newer version.
#Try to pick one version back because later in this series, we'll run an upgrade
VERSION=1.29.1-1.1
sudo apt-get install -y kubelet=$VERSION kubeadm=$VERSION kubectl=$VERSION 
sudo apt-mark hold kubelet kubeadm kubectl containerd



#To install the latest, omit the version parameters
#sudo apt-get install kubelet kubeadm kubectl
#sudo apt-mark hold kubelet kubeadm kubectl


#Check the status of our kubelet and our container runtime.
#The kubelet will enter a inactive/dead state until it's joined
sudo systemctl status kubelet.service 
sudo systemctl status containerd.service 


#Log out of c1-node1 and back on to c1-cp1
exit



#You can also use print-join-command to generate token and print the join command in the proper format
#COPY THIS INTO YOUR CLIPBOARD
kubeadm token create --print-join-command


#Back on the worker node c1-node1, using the Control Plane Node (API Server) IP address or name, the token and the cert has, let's join this Node to our cluster.
ssh aen@c1-node1


#PASTE_JOIN_COMMAND_HERE be sure to add sudo
sudo kubeadm join 172.16.94.10:6443 \
  --token th8kxn.wprtltponkh1d6s0 \
  --discovery-token-ca-cert-hash sha256:41e98ba1e95281e53dfd65935dee7073ee3ef227f3250f4257f97663a19473bd 

#Log out of c1-node1 and back on to c1-cp1
exit


#Back on Control Plane Node, this will say NotReady until the networking pod is created on the new node. 
#Has to schedule the pod, then pull the container.
kubectl get nodes 


#On the Control Plane Node, watch for the calico pod and the kube-proxy to change to Running on the newly added nodes.
kubectl get pods --all-namespaces --watch


#Still on the Control Plane Node, look for this added node's status as ready.
kubectl get nodes


#GO BACK TO THE TOP AND DO THE SAME FOR c1-node2 and c1-node3
#Just SSH into c1-node2 and c1-node3 and run the commands again.



####################################################
############### CreateAKSCluster ###################
####################################################

# This demo will be run from c1-cp1 since kubectl is already installed there.
# This can be run from any system that has the Azure CLI client installed.

#Ensure Azure CLI command line utilitles are installed
#https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-apt?view=azure-cli-latest
AZ_REPO=$(lsb_release -cs)
echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | sudo tee /etc/apt/sources.list.d/azure-cli.list


#Install the gpg key for Microsoft's repository
curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null


sudo apt-get update
sudo apt-get install azure-cli


#Log into our subscription
#Free account - https://azure.microsoft.com/en-us/free/
az login
az account set --subscription "Demonstration Account"


#Create a resource group for the serivces we're going to create
az group create --name "Kubernetes-Cloud" --location centralus


#Let's get a list of the versions available to us
az aks get-versions --location centralus -o table


#Let's create our AKS managed cluster. Use --kubernetes-version to specify a version.
az aks create \
    --resource-group "Kubernetes-Cloud" \
    --generate-ssh-keys \
    --name CSCluster \
    --node-count 3 #default Node count is 3


#If needed, we can download and install kubectl on our local system.
az aks install-cli


#Get our cluster credentials and merge the configuration into our existing config file.
#This will allow us to connect to this system remotely using certificate based user authentication.
az aks get-credentials --resource-group "Kubernetes-Cloud" --name CSCluster


#List our currently available contexts
kubectl config get-contexts


#set our current context to the Azure context
kubectl config use-context CSCluster


#run a command to communicate with our cluster.
kubectl get nodes


#Get a list of running pods, we'll look at the system pods since we don't have anything running.
#Since the API Server is HTTP based...we can operate our cluster over the internet...esentially the same as if it was local using kubectl.
kubectl get pods --all-namespaces


#Let's set to the kubectl context back to our local custer
kubectl config use-context kubernetes-admin@kubernetes


#use kubectl get nodes
kubectl get nodes

#az aks delete --resource-group "Kubernetes-Cloud" --name CSCluster #--yes --no-wait



####################################################
############### CreateGKSCluster ###################
####################################################

#Instructions from this URL: https://cloud.google.com/sdk/docs/quickstart-debian-ubuntu
# Create environment variable for correct distribution
CLOUD_SDK_REPO="cloud-sdk-$(lsb_release -c -s)"


# Add the Cloud SDK distribution URL as a package source
echo "deb http://packages.cloud.google.com/apt $CLOUD_SDK_REPO main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list


# Import the Google Cloud Platform public key
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -


# Update the package list and install the Cloud SDK
sudo apt-get update 
sudo apt-get install google-cloud-sdk


#Authenticate our console session with gcloud
gcloud init --console-only


#Create a named gcloud project
gcloud projects create psdemogke-1 --name="Kubernetes-Cloud"


#Set our current project context
gcloud config set project psdemogke-1


#You may have to adjust your resource limits and enabled billing here based on your subscription here.
#1. Go to https://console.cloud.google.com
#2. Ensure that you are in the project you just created, in the search bar type "Projects" and select the project we just created.
#3. From the Navigation menu on the top left, click Kubernetes Engine
#4. On the Kubernetes Engine landing page click "ENABLE BILLING" and select a billing account from the drop down list. Then click "Set Account" 
#       Then wait until the Kubernete API is enabled, this may take several minutes.


#Tell GKE to create a single zone, three node cluster for us. 3 is the default size.
#We're disabling basic authentication as it's no longer supported after 1.19 in GKE
#For more information on authentication check out this link here:
#   https://cloud.google.com/kubernetes-engine/docs/how-to/api-server-authentication#authenticating_users
gcloud container clusters create cscluster --region us-central1-a --no-enable-basic-auth


#Get our credentials for kubectl, this uses oath rather than certficates.
#See this link for more details on authentication to GKE Clusters
#   https://cloud.google.com/kubernetes-engine/docs/how-to/api-server-authentication#authenticating_users
gcloud container clusters get-credentials cscluster --zone us-central1-a --project psdemogke-1


#Check out out lists of kubectl contexts
kubectl config get-contexts


#set our current context to the GKE context, you may need to update this to your cluster context name.
kubectl config use-context gke_psdemogke-1_us-central1-a_cscluster


#run a command to communicate with our cluster.
kubectl get nodes


#Delete our GKE cluster
#gcloud container clusters delete cscluster --zone=us-central1-a 

#Delete our project.
#gcloud projects delete psdemogke-1


#Get a list of all contexts on this system.
kubectl config get-contexts


#Let's set to the kubectl context back to our local custer
kubectl config use-context kubernetes-admin@kubernetes


#use kubectl get nodes
kubectl get nodes


##########################################################
############### Workingwithyourcluster ###################
##########################################################

#Log into the control plane node c1-cp1/master node c1-master1 
ssh aen@c1-cp1


#Deploying resources imperatively in your cluster.
#kubectl create deployment, creates a Deployment with one replica in it.
#This is pulling a simple hello-world app container image from a container registry.
kubectl create deployment hello-world --image=psk8s.azurecr.io/hello-app:1.0


#But let's deploy a single "bare" pod that's not managed by a controller...
kubectl run hello-world-pod --image=psk8s.azurecr.io/hello-app:1.0


#Let's see of the Deployment creates a single replica and also see if that bare pod is created. 
#You should have two pods here...
# - the one managed by our controller has a the pod template hash in it's name and a unique identifier
# - the bare pod
kubectl get pods
kubectl get pods -o wide


#Remember, k8s is a container orchestrator and it's starting up containers on Nodes.
#Open a second terminal and ssh into the node that hello-world pod is running on.
ssh aen@c1-node[XX]


#When containerd is your container runtime, use crictl to get a listing of the containers running
#Check out this for more details https://kubernetes.io/docs/tasks/debug-application-cluster/crictl
sudo crictl --runtime-endpoint unix:///run/containerd/containerd.sock ps

#Log out of the Node and back into the Control Plane node, c1-cp1
exit


#Back on c1-cp1, we can pull the logs from the container. Which is going to be anything written to stdout. 
#Maybe something went wrong inside our app and our pod won't start. This is useful for troubleshooting.
kubectl logs hello-world-pod


#Starting a process inside a container inside a pod.
#We can use this to launch any process as long as the executable/binary is in the container.
#Launch a shell into the container. Callout that this is on the *pod* network.
kubectl exec -it  hello-world-pod -- /bin/sh
hostname
ip addr
exit


#Remember that first kubectl create deployment we executed, it created a deployment for us.
#Let's look more closely at that deployment
#Deployments are made of ReplicaSets and ReplicaSets create Pods!
kubectl get deployment hello-world
kubectl get replicaset
kubectl get pods


#Let's take a closer look at our Deployment and it's Pods.
#Name, Replicas, and Events. In Events, notice how the ReplicaSet is created by the deployment.
#Deployments are made of ReplicaSets!
kubectl describe deployment hello-world | more


#The ReplicaSet creates the Pods...check out...Name, Controlled By, Replicas, Pod Template, and Events.
#In Events, notice how the ReplicaSet create the Pods
kubectl describe replicaset hello-world | more


#Check out the Name, Node, Status, Controlled By, IPs, Containers, and Events.
#In Events, notice how the Pod is scheduled, the container image is pulled, 
#and then the container is created and then started.
kubectl describe pod hello-world-[tab][tab] | more


#For a deep dive into Deployments check out 'Managing Kubernetes Controllers and Deployments'
#https://www.pluralsight.com/courses/managing-kubernetes-controllers-deployments





#Expose the Deployment as a Service. This will create a Service for the Deployment
#We are exposing our Service on port 80, connecting to an application running on 8080 in our pod.
#Port: Internal Cluster Port, the Service's port. You will point cluster resources here.
#TargetPort: The Pod's Service Port, your application. That one we defined when we started the pods.
kubectl expose deployment hello-world \
     --port=80 \
     --target-port=8080


#Check out the CLUSTER-IP and PORT(S), that's where we'll access this service, from inside the cluster.
kubectl get service hello-world


#We can also get that information from using describe
#Endpoints are IP:Port pairs for each of Pods that that are a member of the Service.
#Right now there is only one...later we'll increase the number of replicas and more Endpoints will be added.
kubectl describe service hello-world


#Access the Service inside the cluster
curl http://$SERVCIEIP:$PORT


#Access a single pod's application directly, useful for troubleshooting.
kubectl get endpoints hello-world
curl http://$ENDPOINT:$TARGETORT


#Using kubectl to generate yaml or json for your deployments
#This includes runtime information...which can be useful for monitoring and config management
#but not as source mainifests for declarative deployments
kubectl get deployment hello-world -o yaml | more 
kubectl get deployment hello-world -o json | more 



#Let's remove everything we created imperatively and start over using a declarative model
#Deleting the deployment will delete the replicaset and then the pods
#We have to delete the bare pod manually since it's not managed by a contorller. 
kubectl get all
kubectl delete service hello-world
kubectl delete deployment hello-world
kubectl delete pod hello-world-pod
kubectl get all



#Deploying resources declaratively in your cluster.
#We can use apply to create our resources from yaml.
#We could write the yaml by hand...but we can use dry-run=client to build it for us
#This can be used a a template for move complex deployments.
kubectl create deployment hello-world \
     --image=psk8s.azurecr.io/hello-app:1.0 \
     --dry-run=client -o yaml | more 


#Let's write this deployment yaml out to file
kubectl create deployment hello-world \
     --image=psk8s.azurecr.io/hello-app:1.0 \
     --dry-run=client -o yaml > deployment.yaml


#The contents of the yaml file show the definition of the Deployment
more deployment.yaml


#Create the deployment...declaratively...in code
kubectl apply -f deployment.yaml


#Generate the yaml for the service
kubectl expose deployment hello-world \
     --port=80 --target-port=8080 \
     --dry-run=client -o yaml | more


#Write the service yaml manifest to file
kubectl expose deployment hello-world \
     --port=80 --target-port=8080 \
     --dry-run=client -o yaml > service.yaml 


#The contents of the yaml file show the definition of the Service
more service.yaml 


#Create the service declaratively
kubectl apply -f service.yaml 


#Check out our current state, Deployment, ReplicaSet, Pod and a Service
kubectl get all


#Scale up our deployment...in code
vi deployment.yaml
Change spec.replicas from 1 to 20
     replicas: 20


#Update our configuration with apply to make that code to the desired state
kubectl apply -f deployment.yaml


#And check the current configuration of our deployment...you should see 20/20
kubectl get deployment hello-world
kubectl get pods | more 


#Repeat the curl access to see the load balancing of the HTTP request
kubectl get service hello-world
curl http://$SERVICEIP:PORT


#We can edit the resources "on the fly" with kubectl edit. But this isn't reflected in our yaml. 
#But this change is persisted in the etcd...cluster store. Change 20 to 30.
kubectl edit deployment hello-world


#The deployment is scaled to 30 and we have 30 pods
kubectl get deployment hello-world


#You can also scale a deployment using scale
kubectl scale deployment hello-world --replicas=40
kubectl get deployment hello-world


#Let's clean up our deployment and remove everything
kubectl delete deployment hello-world
kubectl delete service hello-world
kubectl get all



##########################################################
############### Deployingapplications ####################
##########################################################

#Log into the control plane node c1-cp1/master node c1-master1 
ssh aen@c1-cp1


#Deploying resources imperatively in your cluster.
#kubectl create deployment, creates a Deployment with one replica in it.
#This is pulling a simple hello-world app container image from a container registry.
kubectl create deployment hello-world --image=psk8s.azurecr.io/hello-app:1.0


#But let's deploy a single "bare" pod that's not managed by a controller...
kubectl run hello-world-pod --image=psk8s.azurecr.io/hello-app:1.0


#Let's see of the Deployment creates a single replica and also see if that bare pod is created. 
#You should have two pods here...
# - the one managed by our controller has a the pod template hash in it's name and a unique identifier
# - the bare pod
kubectl get pods
kubectl get pods -o wide


#Remember, k8s is a container orchestrator and it's starting up containers on Nodes.
#Open a second terminal and ssh into the node that hello-world pod is running on.
ssh aen@c1-node[XX]


#When containerd is your container runtime, use crictl to get a listing of the containers running
#Check out this for more details https://kubernetes.io/docs/tasks/debug-application-cluster/crictl
sudo crictl --runtime-endpoint unix:///run/containerd/containerd.sock ps

#Log out of the Node and back into the Control Plane node, c1-cp1
exit


#Back on c1-cp1, we can pull the logs from the container. Which is going to be anything written to stdout. 
#Maybe something went wrong inside our app and our pod won't start. This is useful for troubleshooting.
kubectl logs hello-world-pod


#Starting a process inside a container inside a pod.
#We can use this to launch any process as long as the executable/binary is in the container.
#Launch a shell into the container. Callout that this is on the *pod* network.
kubectl exec -it  hello-world-pod -- /bin/sh
hostname
ip addr
exit


#Remember that first kubectl create deployment we executed, it created a deployment for us.
#Let's look more closely at that deployment
#Deployments are made of ReplicaSets and ReplicaSets create Pods!
kubectl get deployment hello-world
kubectl get replicaset
kubectl get pods


#Let's take a closer look at our Deployment and it's Pods.
#Name, Replicas, and Events. In Events, notice how the ReplicaSet is created by the deployment.
#Deployments are made of ReplicaSets!
kubectl describe deployment hello-world | more


#The ReplicaSet creates the Pods...check out...Name, Controlled By, Replicas, Pod Template, and Events.
#In Events, notice how the ReplicaSet create the Pods
kubectl describe replicaset hello-world | more


#Check out the Name, Node, Status, Controlled By, IPs, Containers, and Events.
#In Events, notice how the Pod is scheduled, the container image is pulled, 
#and then the container is created and then started.
kubectl describe pod hello-world-[tab][tab] | more


#For a deep dive into Deployments check out 'Managing Kubernetes Controllers and Deployments'
#https://www.pluralsight.com/courses/managing-kubernetes-controllers-deployments





#Expose the Deployment as a Service. This will create a Service for the Deployment
#We are exposing our Service on port 80, connecting to an application running on 8080 in our pod.
#Port: Internal Cluster Port, the Service's port. You will point cluster resources here.
#TargetPort: The Pod's Service Port, your application. That one we defined when we started the pods.
kubectl expose deployment hello-world \
     --port=80 \
     --target-port=8080


#Check out the CLUSTER-IP and PORT(S), that's where we'll access this service, from inside the cluster.
kubectl get service hello-world


#We can also get that information from using describe
#Endpoints are IP:Port pairs for each of Pods that that are a member of the Service.
#Right now there is only one...later we'll increase the number of replicas and more Endpoints will be added.
kubectl describe service hello-world


#Access the Service inside the cluster
curl http://$SERVCIEIP:$PORT


#Access a single pod's application directly, useful for troubleshooting.
kubectl get endpoints hello-world
curl http://$ENDPOINT:$TARGETORT


#Using kubectl to generate yaml or json for your deployments
#This includes runtime information...which can be useful for monitoring and config management
#but not as source mainifests for declarative deployments
kubectl get deployment hello-world -o yaml | more 
kubectl get deployment hello-world -o json | more 



#Let's remove everything we created imperatively and start over using a declarative model
#Deleting the deployment will delete the replicaset and then the pods
#We have to delete the bare pod manually since it's not managed by a contorller. 
kubectl get all
kubectl delete service hello-world
kubectl delete deployment hello-world
kubectl delete pod hello-world-pod
kubectl get all



#Deploying resources declaratively in your cluster.
#We can use apply to create our resources from yaml.
#We could write the yaml by hand...but we can use dry-run=client to build it for us
#This can be used a a template for move complex deployments.
kubectl create deployment hello-world \
     --image=psk8s.azurecr.io/hello-app:1.0 \
     --dry-run=client -o yaml | more 


#Let's write this deployment yaml out to file
kubectl create deployment hello-world \
     --image=psk8s.azurecr.io/hello-app:1.0 \
     --dry-run=client -o yaml > deployment.yaml


#The contents of the yaml file show the definition of the Deployment
more deployment.yaml


#Create the deployment...declaratively...in code
kubectl apply -f deployment.yaml


#Generate the yaml for the service
kubectl expose deployment hello-world \
     --port=80 --target-port=8080 \
     --dry-run=client -o yaml | more


#Write the service yaml manifest to file
kubectl expose deployment hello-world \
     --port=80 --target-port=8080 \
     --dry-run=client -o yaml > service.yaml 


#The contents of the yaml file show the definition of the Service
more service.yaml 


#Create the service declaratively
kubectl apply -f service.yaml 


#Check out our current state, Deployment, ReplicaSet, Pod and a Service
kubectl get all


#Scale up our deployment...in code
vi deployment.yaml
Change spec.replicas from 1 to 20
     replicas: 20


#Update our configuration with apply to make that code to the desired state
kubectl apply -f deployment.yaml


#And check the current configuration of our deployment...you should see 20/20
kubectl get deployment hello-world
kubectl get pods | more 


#Repeat the curl access to see the load balancing of the HTTP request
kubectl get service hello-world
curl http://$SERVICEIP:PORT


#We can edit the resources "on the fly" with kubectl edit. But this isn't reflected in our yaml. 
#But this change is persisted in the etcd...cluster store. Change 20 to 30.
kubectl edit deployment hello-world


#The deployment is scaled to 30 and we have 30 pods
kubectl get deployment hello-world


#You can also scale a deployment using scale
kubectl scale deployment hello-world --replicas=40
kubectl get deployment hello-world


#Let's clean up our deployment and remove everything
kubectl delete deployment hello-world
kubectl delete service hello-world
kubectl get all



##########################################################
#################### APIObjects ##########################
##########################################################


ssh aen@c1-cp1
cd ~/content/course/02/demos


#API Discovery
#Get information about our current cluster context, ensure we're logged into the correct cluster.
kubectl config get-contexts


#Change our context if needed by specifying the Name
kubectl config use-context kubernetes-admin@kubernetes


#Get information about the API Server for our current context, which should be kubernetes-admin@kubernetes
kubectl cluster-info


#Get a list of API Resources available in the cluster
kubectl api-resources | more


#Using kubectl explain to see the structure of a resource...specifically it's fields
#In addition to using the API reference on the web this is a great way to discover what it takes to write yaml manifests
kubectl explain pods | more


#Let's look more closely at what we need in pod.spec and pod.spec.containers (image and name are required)
kubectl explain pod.spec | more
kubectl explain pod.spec.containers | more


#Let's check out some YAML and creating a pod with YAML
kubectl apply -f pod.yaml


#Get a list of our currently running pods
kubectl get pods


#Remove our pod...this command blocks and can take a second to complete
kubectl delete pod hello-world




#Working with kubectl dry-run
#Use kubectl dry-run for server side validatation of a manifest...the object will be sent to the API Server.
#dry-run=server will tell you the object was created...but it wasn't...
#it just goes through the whole process but didn't get stored in etcd.
kubectl apply -f deployment.yaml --dry-run=server


#No deployment is created
kubectl get deployments


#Use kubectl dry-run for client side validatation of a manifest...
kubectl apply -f deployment.yaml --dry-run=client


#Let's do that one more time but with an error...replica should be replicas.
kubectl apply -f deployment-error.yaml --dry-run=client


#Use kubectl dry-run client to generate some yaml...for an object
kubectl create deployment nginx --image=nginx --dry-run=client


#Combine dry-run client with -o yaml and you'll get the YAML for the object...in this case a deployment
kubectl create deployment nginx --image=nginx --dry-run=client -o yaml | more


#Can be any object...let's try a pod...
kubectl run pod nginx-pod --image=nginx --dry-run=client -o yaml | more


#We can combine that with IO redirection and store the YAML into a file
kubectl create deployment nginx --image=nginx --dry-run=client -o yaml > deployment-generated.yaml
more deployment-generated.yaml


#And then we can deploy from that manifest...or use it as a building block for more complex manfiests
kubectl apply -f deployment-generated.yaml


#Clean up from that demo...you can use delete with -f to delete all the resources in the manifests
kubectl delete -f deployment-generated.yaml




#Working with kubectl diff
#Create a deployment with 4 replicas
kubectl apply -f deployment.yaml


#Diff that with a deployment with 5 replicas and a new container image...you will see other metadata about the object output too.
kubectl diff -f deployment-new.yaml | more


#Clean up from this demo...you can use delete with -f to delete all the resources in the manifests
kubectl delete -f deployment.yaml



##########################################################
#################### APIObjectVersion ####################
##########################################################

ssh aen@c1-cp1
cd ~/content/course/02/demos


#API Discovery
#Get information about our current cluster context, ensure we're logged into the correct cluster.
kubectl config get-contexts


#Change our context if needed by specifying the Name
kubectl config use-context kubernetes-admin@kubernetes


#Get information about the API Server for our current context, which should be kubernetes-admin@kubernetes
kubectl cluster-info


#Get a list of API Resources available in the cluster
kubectl api-resources | more


#Using kubectl explain to see the structure of a resource...specifically it's fields
#In addition to using the API reference on the web this is a great way to discover what it takes to write yaml manifests
kubectl explain pods | more


#Let's look more closely at what we need in pod.spec and pod.spec.containers (image and name are required)
kubectl explain pod.spec | more
kubectl explain pod.spec.containers | more


#Let's check out some YAML and creating a pod with YAML
kubectl apply -f pod.yaml


#Get a list of our currently running pods
kubectl get pods


#Remove our pod...this command blocks and can take a second to complete
kubectl delete pod hello-world




#Working with kubectl dry-run
#Use kubectl dry-run for server side validatation of a manifest...the object will be sent to the API Server.
#dry-run=server will tell you the object was created...but it wasn't...
#it just goes through the whole process but didn't get stored in etcd.
kubectl apply -f deployment.yaml --dry-run=server


#No deployment is created
kubectl get deployments


#Use kubectl dry-run for client side validatation of a manifest...
kubectl apply -f deployment.yaml --dry-run=client


#Let's do that one more time but with an error...replica should be replicas.
kubectl apply -f deployment-error.yaml --dry-run=client


#Use kubectl dry-run client to generate some yaml...for an object
kubectl create deployment nginx --image=nginx --dry-run=client


#Combine dry-run client with -o yaml and you'll get the YAML for the object...in this case a deployment
kubectl create deployment nginx --image=nginx --dry-run=client -o yaml | more


#Can be any object...let's try a pod...
kubectl run pod nginx-pod --image=nginx --dry-run=client -o yaml | more


#We can combine that with IO redirection and store the YAML into a file
kubectl create deployment nginx --image=nginx --dry-run=client -o yaml > deployment-generated.yaml
more deployment-generated.yaml


#And then we can deploy from that manifest...or use it as a building block for more complex manfiests
kubectl apply -f deployment-generated.yaml


#Clean up from that demo...you can use delete with -f to delete all the resources in the manifests
kubectl delete -f deployment-generated.yaml




#Working with kubectl diff
#Create a deployment with 4 replicas
kubectl apply -f deployment.yaml


#Diff that with a deployment with 5 replicas and a new container image...you will see other metadata about the object output too.
kubectl diff -f deployment-new.yaml | more


#Clean up from this demo...you can use delete with -f to delete all the resources in the manifests
kubectl delete -f deployment.yaml


##########################################################
#################### AnatomyAPIRequest ###################
##########################################################

#Anatomy of an API Request
#Creating a pod with YAML
kubectl apply -f pod.yaml

#Get a list of our currently running Pods
kubectl get pod hello-world

#We can use the -v option to increase the verbosity of our request.
#Display requested resource URL. Focus on VERB, API Path and Response code
kubectl get pod hello-world -v 6 

#Same output as 6, add HTTP Request Headers. Focus on application type, and User-Agent
kubectl get pod hello-world -v 7 

#Same output as 7, adds Response Headers and truncated Response Body.
kubectl get pod hello-world -v 8 

#Same output as 8, add full Response. Focus on the bottom, look for metadata
kubectl get pod hello-world -v 9 

#Start up a kubectl proxy session, this will authenticate use to the API Server
#Using our local kubeconfig for authentication and settings, updated head to only return 10 lines.
kubectl proxy &
curl http://localhost:8001/api/v1/namespaces/default/pods/hello-world | head -n 10

fg
ctrl+c

#Watch, Exec and Log Requests
#A watch on Pods will watch on the resourceVersion on api/v1/namespaces/default/Pods
kubectl get pods --watch -v 6 &

#We can see kubectl keeps the TCP session open with the server...waiting for data.
netstat -plant | grep kubectl

#Delete the pod and we see the updates are written to our stdout. Watch stays, since we're watching All Pods in the default namespace.
kubectl delete pods hello-world

#But let's bring our Pod back...because we have more demos.
kubectl apply -f pod.yaml

#And kill off our watch
fg
ctrl+c

#Accessing logs
kubectl logs hello-world
kubectl logs hello-world -v 6

#Start kubectl proxy, we can access the resource URL directly.
kubectl proxy &
curl http://localhost:8001/api/v1/namespaces/default/pods/hello-world/log 

#Kill our kubectl proxy, fg then ctrl+c
fg
ctrl+c

#Authentication failure Demo
cp ~/.kube/config  ~/.kube/config.ORIG

#Make an edit to our username changing user: kubernetes-admin to user: kubernetes-admin1
vi ~/.kube/config

#Try to access our cluster, and we see GET https://172.16.94.10:6443/api?timeout=32s 403 Forbidden in 5 milliseconds
#Enter in incorrect information for username and password
kubectl get pods -v 6

#Let's put our backup kubeconfig back
cp ~/.kube/config.ORIG ~/.kube/config

#Test out access to the API Server
kubectl get pods 

#Missing resources, we can see the response code for this resources is 404...it's Not Found.
kubectl get pods nginx-pod -v 6

#Let's look at creating and deleting a deployment. 
#We see a query for the existence of the deployment which results in a 404, then a 201 OK on the POST to create the deployment which suceeds.
kubectl apply -f deployment.yaml -v 6

#Get a list of the Deployments
kubectl get deployment 

#Clean up when we're finished. We see a DELETE 200 OK and a GET 200 OK.
kubectl delete deployment hello-world -v 6
kubectl delete pod hello-world


##########################################################
#################### Namespaces ##########################
##########################################################

#Demo requires nodes c1-cp1, c1-node1, c1-node2 and c1-node3
ssh aen@c1-cp1
cd ~/content/course/03/demos

#Create a collection of pods with labels assinged to each
more CreatePodsWithLabels.yaml
kubectl apply -f CreatePodsWithLabels.yaml

#Look at all the Pod labels in our cluster
kubectl get pods --show-labels

#Look at one Pod's labels in our cluster
kubectl describe pod nginx-pod-1 | head

#Query labels and selectors
kubectl get pods --selector tier=prod
kubectl get pods --selector tier=qa
kubectl get pods -l tier=prod
kubectl get pods -l tier=prod --show-labels

#Selector for multiple labels and adding on show-labels to see those labels in the output
kubectl get pods -l 'tier=prod,app=MyWebApp' --show-labels
kubectl get pods -l 'tier=prod,app!=MyWebApp' --show-labels
kubectl get pods -l 'tier in (prod,qa)'
kubectl get pods -l 'tier notin (prod,qa)'

#Output a particluar label in column format
kubectl get pods -L tier
kubectl get pods -L tier,app

#Edit an existing label
kubectl label pod nginx-pod-1 tier=non-prod --overwrite
kubectl get pod nginx-pod-1 --show-labels

#Adding a new label
kubectl label pod nginx-pod-1 another=Label
kubectl get pod nginx-pod-1 --show-labels

#Removing an existing label
kubectl label pod nginx-pod-1 another-
kubectl get pod nginx-pod-1 --show-labels

#Performing an operation on a collection of pods based on a label query
kubectl label pod --all tier=non-prod --overwrite
kubectl get pod --show-labels

#Delete all pods matching our non-prod label
kubectl delete pod -l tier=non-prod

#And we're left with nothing.
kubectl get pods --show-labels

#Kubernetes Resource Management
#Start a Deployment with 3 replicas, open deployment-label.yaml
kubectl apply -f deployment-label.yaml

#Expose our Deployment as  Service, open service.yaml
kubectl apply -f service.yaml

#Look at the Labels and Selectors on each resource, the Deployment, ReplicaSet and Pod
#The deployment has a selector for app=hello-world
kubectl describe deployment hello-world

#The ReplicaSet has labels and selectors for app and the current pod-template-hash
#Look at the Pod Template and the labels on the Pods created
kubectl describe replicaset hello-world

#The Pods have labels for app=hello-world and for the pod-temlpate-hash of the current ReplicaSet
kubectl get pods --show-labels

#Edit the label on one of the Pods in the ReplicaSet, change the pod-template-hash
kubectl label pod PASTE_POD_NAME_HERE pod-template-hash=DEBUG --overwrite

#The ReplicaSet will deploy a new Pod to satisfy the number of replicas. Our relabeled Pod still exists.
kubectl get pods --show-labels

#Let's look at how Services use labels and selectors, check out services.yaml
kubectl get service

#The selector for this serivce is app=hello-world, that pod is still being load balanced to!
kubectl describe service hello-world 

#Get a list of all IPs in the service, there's 5...why?
kubectl describe endpoints hello-world

#Get a list of pods and their IPs
kubectl get pod -o wide

#To remove a pod from load balancing, change the label used by the service's selector.
#The ReplicaSet will respond by placing another pod in the ReplicaSet
kubectl get pods --show-labels
kubectl label pod PASTE_POD_NAME_HERE app=DEBUG --overwrite

#Check out all the labels in our pods
kubectl get pods --show-labels

#Look at the registered endpoint addresses. Now there's 4
kubectl describe endpoints hello-world

#To clean up, delete the deployment, service and the Pod removed from the replicaset
kubectl delete deployment hello-world
kubectl delete service hello-world
kubectl delete pod PASTE_POD_NAME_HERE

#Scheduling a pod to a node
#Scheduling is a much deeper topic, we're focusing on how labels can be used to influence it here.
kubectl get nodes --show-labels 

#Label our nodes with something descriptive
kubectl label node c1-node2 disk=local_ssd
kubectl label node c1-node3 hardware=local_gpu

#Query our labels to confirm.
kubectl get node -L disk,hardware

#Create three Pods, two using nodeSelector, one without.
more PodsToNodes.yaml
kubectl apply -f PodsToNodes.yaml

#View the scheduling of the pods in the cluster.
kubectl get node -L disk,hardware
kubectl get pods -o wide

#Clean up when we're finished, delete our labels and Pods
kubectl label node c1-node2 disk-
kubectl label node c1-node3 hardware-
kubectl delete pod nginx-pod
kubectl delete pod nginx-pod-gpu
kubectl delete pod nginx-pod-ssd



##########################################################
#################### Labels ##############################
##########################################################

#Demo requires nodes c1-cp1, c1-node1, c1-node2 and c1-node3
ssh aen@c1-cp1
cd ~/content/course/03/demos

#Create a collection of pods with labels assinged to each
more CreatePodsWithLabels.yaml
kubectl apply -f CreatePodsWithLabels.yaml

#Look at all the Pod labels in our cluster
kubectl get pods --show-labels

#Look at one Pod's labels in our cluster
kubectl describe pod nginx-pod-1 | head

#Query labels and selectors
kubectl get pods --selector tier=prod
kubectl get pods --selector tier=qa
kubectl get pods -l tier=prod
kubectl get pods -l tier=prod --show-labels

#Selector for multiple labels and adding on show-labels to see those labels in the output
kubectl get pods -l 'tier=prod,app=MyWebApp' --show-labels
kubectl get pods -l 'tier=prod,app!=MyWebApp' --show-labels
kubectl get pods -l 'tier in (prod,qa)'
kubectl get pods -l 'tier notin (prod,qa)'

#Output a particluar label in column format
kubectl get pods -L tier
kubectl get pods -L tier,app

#Edit an existing label
kubectl label pod nginx-pod-1 tier=non-prod --overwrite
kubectl get pod nginx-pod-1 --show-labels

#Adding a new label
kubectl label pod nginx-pod-1 another=Label
kubectl get pod nginx-pod-1 --show-labels

#Removing an existing label
kubectl label pod nginx-pod-1 another-
kubectl get pod nginx-pod-1 --show-labels

#Performing an operation on a collection of pods based on a label query
kubectl label pod --all tier=non-prod --overwrite
kubectl get pod --show-labels

#Delete all pods matching our non-prod label
kubectl delete pod -l tier=non-prod

#And we're left with nothing.
kubectl get pods --show-labels

#Kubernetes Resource Management
#Start a Deployment with 3 replicas, open deployment-label.yaml
kubectl apply -f deployment-label.yaml

#Expose our Deployment as  Service, open service.yaml
kubectl apply -f service.yaml

#Look at the Labels and Selectors on each resource, the Deployment, ReplicaSet and Pod
#The deployment has a selector for app=hello-world
kubectl describe deployment hello-world

#The ReplicaSet has labels and selectors for app and the current pod-template-hash
#Look at the Pod Template and the labels on the Pods created
kubectl describe replicaset hello-world

#The Pods have labels for app=hello-world and for the pod-temlpate-hash of the current ReplicaSet
kubectl get pods --show-labels

#Edit the label on one of the Pods in the ReplicaSet, change the pod-template-hash
kubectl label pod PASTE_POD_NAME_HERE pod-template-hash=DEBUG --overwrite

#The ReplicaSet will deploy a new Pod to satisfy the number of replicas. Our relabeled Pod still exists.
kubectl get pods --show-labels

#Let's look at how Services use labels and selectors, check out services.yaml
kubectl get service

#The selector for this serivce is app=hello-world, that pod is still being load balanced to!
kubectl describe service hello-world 

#Get a list of all IPs in the service, there's 5...why?
kubectl describe endpoints hello-world

#Get a list of pods and their IPs
kubectl get pod -o wide

#To remove a pod from load balancing, change the label used by the service's selector.
#The ReplicaSet will respond by placing another pod in the ReplicaSet
kubectl get pods --show-labels
kubectl label pod PASTE_POD_NAME_HERE app=DEBUG --overwrite

#Check out all the labels in our pods
kubectl get pods --show-labels

#Look at the registered endpoint addresses. Now there's 4
kubectl describe endpoints hello-world

#To clean up, delete the deployment, service and the Pod removed from the replicaset
kubectl delete deployment hello-world
kubectl delete service hello-world
kubectl delete pod PASTE_POD_NAME_HERE

#Scheduling a pod to a node
#Scheduling is a much deeper topic, we're focusing on how labels can be used to influence it here.
kubectl get nodes --show-labels 

#Label our nodes with something descriptive
kubectl label node c1-node2 disk=local_ssd
kubectl label node c1-node3 hardware=local_gpu

#Query our labels to confirm.
kubectl get node -L disk,hardware

#Create three Pods, two using nodeSelector, one without.
more PodsToNodes.yaml
kubectl apply -f PodsToNodes.yaml

#View the scheduling of the pods in the cluster.
kubectl get node -L disk,hardware
kubectl get pods -o wide

#Clean up when we're finished, delete our labels and Pods
kubectl label node c1-node2 disk-
kubectl label node c1-node3 hardware-
kubectl delete pod nginx-pod
kubectl delete pod nginx-pod-gpu
kubectl delete pod nginx-pod-ssd

##########################################################
#################### Pods ##############################
##########################################################

ssh aen@c1-cp1
cd ~/content/course/04/demos/

#Start up kubectl get events --watch and background it.
kubectl get events --watch &

#Create a pod...we can see the scheduling, container pulling and container starting.
kubectl apply -f pod.yaml

#Start a Deployment with 1 replica. We see the deployment created, scaling the replica set and the replica set starting the first pod
kubectl apply -f deployment.yaml

#Scale a Deployment to 2 replicas. We see the scaling the replica set and the replica set starting the second pod
kubectl scale deployment hello-world --replicas=2

#We start off with the replica set scaling to 1, then  Pod deletion, then the Pod killing the container 
kubectl scale deployment hello-world --replicas=1

kubectl get pods

#Let's use exec a command inside our container, we can see the GET and POST API requests through the API server to reach the pod.
kubectl -v 6 exec -it PASTE_POD_NAME_HERE -- /bin/sh
ps
exit

#Let's look at the running container/pod from the process level on a Node.
kubectl get pods -o wide
ssh aen@c1-node[xx]
ps -aux | grep hello-app
exit

#Now, let's access our Pod's application directly, without a service and also off the Pod network.
kubectl port-forward PASTE_POD_NAME_HERE 80:8080

#Let's do it again, but this time with a non-priviledged port
kubectl port-forward PASTE_POD_NAME_HERE 8080:8080 &

#We can point curl to localhost, and kubectl port-forward will send the traffic through the API server to the Pod
curl http://localhost:8080

#Kill our port forward session.
fg
ctrl+c

kubectl delete deployment hello-world
kubectl delete pod hello-world-pod

#Kill off the kubectl get events
fg
ctrl+c


#Static pods
#Quickly create a Pod manifest using kubectl run with dry-run and -o yaml...copy that into your clipboard
kubectl run hello-world --image=psk8s.azurecr.io/hello-app:2.0 --dry-run=client -o yaml --port=8080 

#Log into a node...
ssh aen@c1-node1

#Find the staticPodPath:
sudo cat /var/lib/kubelet/config.yaml


#Create a Pod manifest in the staticPodPath...paste in the manifest we created above
sudo vi /etc/kubernetes/manifests/mypod.yaml
ls /etc/kubernetes/manifests

#Log out of c1-node1 and back onto c1-cp1
exit

#Get a listing of pods...the pods name is podname + node name
kubectl get pods -o wide


#Try to delete the pod...
kubectl delete pod hello-world-c1-node1


#Its still there...
kubectl get pods 


#Remove the static pod manifest on the node
ssh aen@c1-node1
sudo rm /etc/kubernetes/manifests/mypod.yaml

#Log out of c1-node1 and back onto c1-cp1
exit

#The pod is now gone.
kubectl get pods 


##########################################################
#################### Multi-containerPods #################
##########################################################

ssh aen@c1-cp1
cd ~/content/course/04/demos/

#Review the code for a multi-container pod, the volume webcontent is an emptyDir...essentially a temporary file system.
#This is mounted in the containers at mountPath, in two different locations inside the container.
#As producer writes data, consumer can see it immediatly since it's a shared file system.
more multicontainer-pod.yaml

#Let's create our multi-container Pod.
kubectl apply -f multicontainer-pod.yaml

#Let's connect to our Pod...not specifying a name defaults to the first container in the configuration
kubectl exec -it multicontainer-pod -- /bin/sh
ls -la /var/log
tail /var/log/index.html
exit

#Let's specify a container name and access the consumer container in our Pod
kubectl exec -it multicontainer-pod --container consumer -- /bin/sh
ls -la /usr/share/nginx/html
tail /usr/share/nginx/html/index.html
exit

#This application listens on port 80, we'll forward from 8080->80
kubectl port-forward multicontainer-pod 8080:80 &
curl http://localhost:8080

#Kill our port-forward.
fg
ctrl+c

kubectl delete pod multicontainer-pod

##########################################################
#################### Init-containerPods ##################
##########################################################

ssh aen@c1-cp1
cd ~/content/course/04/demos/


#Use a watch to watch the progress
#Each init container run to completion then the app container will start and the Pod status changes to Running.
kubectl get pods --watch &


#Create the Pod with 2 init containers...
#each init container will be processed serially until completion before the main application container is started
kubectl apply -f init-containers.yaml


#Review the Init-Containers section and you will see each init container state is 'Teminated and Completed' and the main app container is Running
#Looking at Events...you should see each init container starting, serially...
#and then the application container starting last once the others have completed
kubectl describe pods init-containers | more 


#Delete the pod
kubectl delete -f init-containers.yaml

#Kill the watch
fg
ctrl+c


##########################################################
#################### Pod-Lifecycle #######################
##########################################################

ssh aen@c1-cp1
cd ~/content/course/04/demos/

#Start up kubectl get events --watch and background it.
kubectl get events --watch &
clear

#Create a pod...we can see the scheduling, container pulling and container starting.
kubectl apply -f pod.yaml

#We've used exec to launch a shell before, but we can use it to launch ANY program inside a container.
#Let's use killall to kill the hello-app process inside our container
kubectl exec -it hello-world-pod -- /bin/sh 
ps
exit

#We still have our kubectl get events running in the background, so we see if re-create the container automatically.
kubectl exec -it hello-world-pod -- /usr/bin/killall hello-app

#Our restart count increased by 1 after the container needed to be restarted.
kubectl get pods

#Look at Containers->State, Last State, Reason, Exit Code, Restart Count and Events
#This is because the container restart policy is Always by default
kubectl describe pod hello-world-pod

#Cleanup time
kubectl delete pod hello-world-pod

#Kill our watch
fg
ctrl+c

#Remember...we can ask the API server what it knows about an object, in this case our restartPolicy
kubectl explain pods.spec.restartPolicy

#Create our pods with the restart policy
more pod-restart-policy.yaml
kubectl apply -f pod-restart-policy.yaml

#Check to ensure both pods are up and running, we can see the restarts is 0
kubectl get pods 

#Let's kill our apps in both our pods and see how the container restart policy reacts
kubectl exec -it hello-world-never-pod -- /usr/bin/killall hello-app
kubectl get pods

#Review container state, reason, exit code, ready and contitions Ready, ContainerReady
kubectl describe pod hello-world-never-pod

#let's use killall to terminate the process inside our container. 
kubectl exec -it hello-world-onfailure-pod -- /usr/bin/killall hello-app

#We'll see 1 restart on the pod with the OnFailure restart policy.
kubectl get pods 

#Let's kill our app again, with the same signal.
kubectl exec -it hello-world-onfailure-pod -- /usr/bin/killall hello-app

#Check its status, which is now Error too...why? The backoff.
kubectl get pods 

#Let's check the events, we hit the backoff loop. 10 second wait. Then it will restart.
#Also check out State and Last State.
kubectl describe pod hello-world-onfailure-pod 

#Check its status, should be Running...after the Backoff timer expires.
kubectl get pods 

#Now let's look at our Pod statuses
kubectl delete pod hello-world-never-pod
kubectl delete pod hello-world-onfailure-pod


##########################################################
#################### Probes ##############################
##########################################################

ssh aen@c1-cp1
cd ~/content/course/04/demos/

#Start a watch to see the events associated with our probes.
kubectl get events --watch &
clear

#We have a single container pod app, in a Deployment that has both a liveness probe and a readiness probe
more container-probes.yaml

#Send in our deployment, after 10 seconds, our liveness and readiness probes will fail.
#The liveness probe will kill the current pod, and recreate one.
kubectl apply -f container-probes.yaml

#kill our watch
fg
ctrl+c

#We can see that our container isn't ready 0/1 and it's Restarts are increasing.
kubectl get pods

#Let's figure out what's wrong
#1. We can see in the events. The Liveness and Readiness probe failures.
#2. Under Containers, Liveness and Readiness, we can see the current configuration. And the current probe configuration. Both are pointing to 8081.
#3. Under Containers, Ready and Container Contidtions, we can see that the container isn't ready.
#4. Our Container Port is 8080, that's what we want our probes, probings. 
kubectl describe pods

#So let's go ahead and change the probes to 8080
vi container-probes.yaml

#And send that change into the API Server for this deployment.
kubectl apply -f container-probes.yaml

#Confirm our probes are pointing to the correct container port now, which is 8080.
kubectl describe pods

#Let's check our status, a couple of things happened there.
#1. Our Deployment ReplicaSet created a NEW Pod, when we pushed in the new deployment configuration.
#2. It's not immediately ready because of our initialDelaySeconds which is 10 seconds.
#3. If we wait long enough, the livenessProbe will kill the original Pod and it will go away.
#4. Leaving us with the one pod in our Deployment's ReplicaSet
kubectl get pods 

kubectl delete deployment hello-world



#Let's start up a watch on kubectl get events
kubectl get events --watch &
clear

#Create our deployment with a faulty startup probe...
#You'll see failures since the startup probe is looking for 8081...
#but you won't see the liveness or readiness probes executed
#The container will be restarted after 1 failures failureThreshold defaults to 3...this can take up to 30 seconds
#The container restart policy default is Always...so it will restart.
kubectl apply -f container-probes-startup.yaml


#Do you see any container restarts?  You should see 1.
kubectl get pods


#Change the startup probe from 8081 to 8080
kubectl apply -f container-probes-startup.yaml


#Our pod should be up and Ready now.
kubectl get pods

fg
ctrl+c

kubectl delete -f container-probes-startup.yaml


##########################################################
#################### Kube-system #########################
##########################################################

#Log into the Control Plane Node to drive these demos.
ssh aen@c1-cp1
cd ~/content/course/02/demos


#Demo 1 - Examining System Pods and their Controllers

#Inside the kube-system namespace, there's a collection of controllers supporting parts of the cluster's control plane
#How'd they get started since there's no cluster when they need to come online? Static Pod Manifests
kubectl get --namespace kube-system all 


#Let's look more closely at one of those deployments, requiring 2 pods up and runnning at all times.
kubectl get --namespace kube-system deployments coredns


#Daemonset Pods run on every node in the cluster by default, as new nodes are added these will be deployed to those nodes.
#There's a Pod for our Pod network, calico and one for the kube-proxy.
kubectl get --namespace kube-system daemonset


#We have 4 nodes, that's why for each daemonset they have 4 Pods.
kubectl get nodes



##########################################################
#################### DeploymentBasices ###################
##########################################################

#Log into the Control Plane Node to drive these demos.
ssh aen@c1-cp1
cd ~/content/course/02/demos


#Demo 2 Creating a Deployment Imperatively, with kubectl create,
#you have lot's of options available to you such as image, container ports, and replicas
kubectl create deployment hello-world --image=psk8s.azurecr.io/hello-app:1.0
kubectl scale deployment hello-world --replicas=5


#These two commands can be combined into one command if needed
#kubectl create deployment hello-world --image=psk8s.azurecr.io/hello-app:1.0 --replicas=5


#Check out the status of our imperative deployment
kubectl get deployment 


#Now let's delete that and move towards declarative configuration.
kubectl delete deployment hello-world




#Demo 1.b - Declaratively
#Simple Deployment
#Let's start off declaratively creating a deployment with a service.
kubectl apply -f deployment.yaml


#Check out the status of our deployment, which creates the ReplicaSet, which creates our Pods
kubectl get deployments hello-world


#The first replica set created in our deployment, which has the responsibility of keeping
#of maintaining the desired state of our application but starting and keeping 5 pods online. 
#In the name of the replica set is the pod-template-hash
kubectl get replicasets


#The actual pods as part of this replicaset, we know these pods belong to the replicaset because of the
#pod-template-hash in the name
kubectl get pods


#But also by looking at the 'Controlled By' property
kubectl describe pods | head -n 20


#It's the job of the deployment-controller to maintain state. Let's look at it a litte closer
#The selector defines which pods are a member of this deployment.
#Replicas define the current state of the deployment, we'll dive into what each one of these means later in the course.
#In Events, you can see the creation and scaling of the replica set to 5
kubectl describe deployment


#Remove our resources
kubectl delete deployment hello-world
kubectl delete service hello-world



##########################################################
#################### ReplicaSet ##########################
##########################################################


#Log into the Control Plane Node to drive these demos.
ssh aen@c1-cp1
cd ~/content/course/02/demos


#Demo 1 - Deploy a Deployment which creates a ReplicaSet
kubectl apply -f deployment.yaml
kubectl get replicaset


#Let's look at the selector for this one...and the labels in the pod template
kubectl describe replicaset hello-world


#Let's delete this deployment which will delete the replicaset
kubectl delete deployment hello-world
kubectl get replicaset



#Deploy a ReplicaSet with matchExpressions
kubectl apply -f deployment-me.yaml


#Check on the status of our ReplicaSet
kubectl get replicaset


#Let's look at the Selector for this one...and the labels in the pod template
kubectl describe replicaset hello-world


#Demo 2 - Deleting a Pod in a ReplicaSet, application will self-heal itself
kubectl get pods
kubectl delete pods hello-world-[tab][tab]
kubectl get pods




#Demo 3 - Isolating a Pod from a ReplicaSet
#For more coverage on this see, Managing the Kubernetes API Server and Pods - Module 2 - Managing Objects with Labels, Annotations, and Namespaces
kubectl get pods --show-labels


#Edit the label on one of the Pods in the ReplicaSet, the replicaset controller will create a new pod
kubectl label pod hello-world-[tab][tab] app=DEBUG --overwrite
kubectl get pods --show-labels




#Demo 4 - Taking over an existing Pod in a ReplicaSet, relabel that pod to bring 
#it back into the scope of the replicaset...what's kubernetes going to do?
kubectl label pod hello-world-[tab][tab] app=hello-world-pod-me --overwrite


#One Pod will be terminated, since it will maintain the desired number of replicas at 5
kubectl get pods --show-labels
kubectl describe ReplicaSets




#Demo 5 - Node failures in ReplicaSets
#Shutdown a node
ssh c1-node3
sudo shutdown -h now


#c1-node3 Status Will go NotReady...takes about 1 minute.
kubectl get nodes --watch


#But there's a Pod still on c1-node3...wut? 
#Kubernetes is protecting against transient issues. Assumes the Pod is still running...
kubectl get pods -o wide


#Start up c1-node3, break out of watch when Node reports Ready, takes about 15 seconds
kubectl get nodes --watch


#That Pod that was on c1-node3 goes to Status Unknown then it will be restarted on that Node.
kubectl get pods -o wide 


#It will start the container back up on the Node c1-node3...see Restarts is now 1, takes about 10 seconds
#The pod didn't get rescheduled, it's still there, the container restart policy restarts the container which 
#starts at 10 seconds and defaults to Always. We covered this in detail in my course "Managing the Kuberentes API Server and Pods"
kubectl get pods -o wide --watch

#Shutdown a node again...
ssh c1-node3
sudo shutdown -h now


#Let's set a watch and wait...about 5 minutes and see what kubernetes will do.
#Because of the --pod-eviction-timeout duration setting on the kube-controller-manager, this pod will get killed after 5 minutes.
kubectl get pods --watch


#Orphaned Pod goes Terminating and a new Pod will be deployed in the cluster.
#If the Node returns the Pod will be deleted, if the Node does not, we'll have to delete it
kubectl get pods -o wide


#And go start c1-node3 back up again and see if those pods get deleted :)


#let's clean up...
kubectl delete deployment hello-world
kubectl delete service hello-world


##########################################################
#################### deployments #########################
##########################################################

ssh aen@c1-cp1
cd ~/content/course/03/demos/

#Demo 1 - Updating a Deployment and checking our rollout status
#Let's start off with rolling out v1
kubectl apply -f deployment.yaml


#Check the status of the deployment
kubectl get deployment hello-world


#Now let's apply that deployment, run both this and line 18 at the same time.
kubectl apply -f deployment.v2.yaml


#Let's check the status of that rollout, while the command blocking your deployment is in the Progressing status.
kubectl rollout status deployment hello-world


#Expect a return code of 0 from kubectl rollout status...that's how we know we're in the Complete status.
echo $?


#Let's walk through the description of the deployment...
#Check out Replicas, Conditions and Events OldReplicaSet (will only be populated during a rollout) and NewReplicaSet
#Conditions (more information about our objects state):
#     Available      True    MinimumReplicasAvailable
#     Progressing    True    NewReplicaSetAvailable (when true, deployment is still progressing or complete)
kubectl describe deployments hello-world


#Both replicasets remain, and that will become very useful shortly when we use a rollback :)
kubectl get replicaset


#The NewReplicaSet, check out labels, replicas, status and pod-template-hash
kubectl describe replicaset hello-world-86666f466d


#The OldReplicaSet, check out labels, replicas, status and pod-template-hash
kubectl describe replicaset hello-world-75d856dc89



##########################################################
#################### deployments #########################
##########################################################

ssh aen@c1-cp1
cd ~/content/course/03/demos/

#Demo 2.1 - Updating to a non-existent image. 
#Delete any current deployments, because we're interested in the deploy state changes.
kubectl delete deployment hello-world
kubectl delete service hello-world

#Create our v1 deployment, then update it to v2
kubectl apply -f deployment.yaml
kubectl apply -f deployment.v2.yaml


#Observe behavior since new image wasn’t available, the ReplicaSet doesn't go below maxUnavailable
kubectl apply -f deployment.broken.yaml


#Why isn't this finishing...? after progressDeadlineSeconds which we set to 10 seconds (defaults to 10 minutes)
kubectl rollout status deployment hello-world


#Expect a return code of 1 from kubectl rollout status...that's how we know we're in the failed status.
echo $?


#Let's check out Pods, ImagePullBackoff/ErrImagePull...ah an error in our image definition.
#Also, it stopped the rollout at 5, that's kind of nice isn't it?
#And 8 are online, let's look at why.
kubectl get pods


#What is maxUnavailable? 25%...So only two Pods in the ORIGINAL ReplicaSet are offline and 8 are online.
#What is maxSurge? 25%? So we have 13 total Pods, or 25% in addition to Desired number.
#Look at Replicas and OldReplicaSet 8/8 and NewReplicaSet 5/5.
#  Available      True    MinimumReplicasAvailable
#  Progressing    False   ProgressDeadlineExceeded
kubectl describe deployments hello-world 


#Let's sort this out now...check the rollout history, but which revision should we rollback to?
kubectl rollout history deployment hello-world


#It's easy in this example, but could be harder for complex systems.
#Let's look at our revision Annotation, should be 3
kubectl describe deployments hello-world | head

#We can also look at the changes applied in each revision to see the new pod templates.
kubectl rollout history deployment hello-world --revision=2
kubectl rollout history deployment hello-world --revision=3


#Let's undo our rollout to revision 2, which is our v2 container.
kubectl rollout undo deployment hello-world --to-revision=2
kubectl rollout status deployment hello-world
echo $?


#We're back to Desired of 10 and 2 new Pods where deployed using the previous Deployment Replicas/Container Image.
kubectl get pods


#Let's delete this Deployment and start over with a new Deployment.
kubectl delete deployment hello-world
kubectl delete service hello-world


###Examine deployment.probes-1.yaml, review strategy settings, revisionhistory, and readinessProbe settings###

####QUICKLY run these two commands or as one block.####
#Demo 3 - Controlling the rate and update strategy of a Deployment update.
#Let's deploy a Deployment with Readiness Probes
kubectl apply -f deployment.probes-1.yaml --record


#Available is still 0 because of our Readiness Probe's initialDelaySeconds is 10 seconds.
#Also, look there's a new annotaion for our change-cause
#And check the Conditions, 
#   Progressing   True    NewReplicaSetCreated or ReplicaSetUpdated - depending on the state.
#   Available     False   MinimumReplicasUnavailable
kubectl describe deployment hello-world
####################################################

#Check again, Replicas and Conditions, all Pods should be online and ready.
#   Available      True    MinimumReplicasAvailable
#   Progressing    True    NewReplicaSetAvailable
kubectl describe deployment hello-world


#Let's update from v1 to v2 with Readiness Probes Controlling the rollout, and record our rollout
diff deployment.probes-1.yaml deployment.probes-2.yaml
kubectl apply -f deployment.probes-2.yaml --record


#Lots of pods, most are not ready yet, but progressing...how do we know it's progressing?
kubectl get replicaset


#Check again, Replicas and Conditions. 
#Progressing is now ReplicaSetUpdated, will change to NewReplicaSetAvailable when it's Ready
#NewReplicaSet is THIS current RS, OldReplicaSet is populated during a Rollout, otherwise it's <None>
#We used the update strategy settings of max unavailable and max surge to slow this rollout down.
#This update takes about a minute to rollout
kubectl describe deployment hello-world


#Let's update again, but I'm not going to tell you what I changed, we're going to troubleshoot it together
kubectl apply -f deployment.probes-3.yaml --record


#We stall at 4 out of 20 replicas updated...let's look
kubectl rollout status deployment hello-world


#Let's check the status of the Deployment, Replicas and Conditions, 
#22 total (20 original + 2 max surge)
#18 available (20 original - 2 (10%) in the old RS)
#4 Unavailable, (only 2 pods in the old RS are offline, 4 in the new RS are not READY)
#  Available      True    MinimumReplicasAvailable
#  Progressing    True    ReplicaSetUpdated 
kubectl describe deployment hello-world


#Let's look at our ReplicaSets, no Pods in the new RS hello-world-89579fd85 are READY, but 4 our deployed.
#That RS with Desired 0 is from our V1 deployment, 18 is from our V2 deployment.
kubectl get replicaset


#Ready...that sounds familiar, let's check the deployment again
#What keeps a pod from reporting ready? A Readiness Probe...see that Readiness Probe, wrong port ;)
kubectl describe deployment hello-world
 

#We can read the Deployment's rollout history, and see our CHANGE-CAUSE annotations
kubectl rollout history deployment hello-world


#Let's rollback to revision 2 to undo that change...
kubectl rollout history deployment hello-world --revision=3
kubectl rollout history deployment hello-world --revision=2
kubectl rollout undo deployment hello-world --to-revision=2


#And check out our deployment to see if we get 20 Ready replicas
kubectl describe deployment | head
kubectl get deployment

#Let's clean up
kubectl delete deployment hello-world
kubectl delete service hello-world




#Restarting a deployment. Create a fresh deployment so we have easier to read logs.
kubectl create deployment hello-world --image=psk8s.azurecr.io/hello-app:1.0 --replicas=5


#Check the status of the deployment
kubectl get deployment


#Check the status of the pods...take note of the pod template hash in the NAME and the AGE
kubectl get pods 


#Let's restart a deployment
kubectl rollout restart deployment hello-world 


#You get a new replicaset and the pods in the old replicaset are shutdown and the new replicaset are started up
kubectl describe deployment hello-world


#All new pods in the replicaset 
kubectl get pods 


#clean up from this demo
kubectl delete deployment hello-world


##########################################################
#################### deployments #########################
##########################################################

ssh aen@c1-cp1
cd ~/content/course/03/demos/

#Demo 1 - Creating and Scaling a Deployment.
#Let's start off imperatively creating a deployment and scaling it...
#To create a deployment, we need kubectl create deployment
kubectl create deployment hello-world --image=psk8s.azurecr.io/hello-app:1.0


#Check out the status of our deployment, we get 1 Replica
kubectl get deployment hello-world


#Let's scale our deployment from 1 to 10 replicas
kubectl scale deployment hello-world --replicas=10


#Check out the status of our deployment, we get 10 Replicas
kubectl get deployment hello-world


#But we're going to want to use declarative deployments in yaml, so let's delete this.
kubectl delete deployment hello-world


#Deploy our Deployment via yaml, look inside deployment.yaml first.
kubectl apply -f deployment.yaml 


#Check the status of our deployment
kubectl get deployment hello-world


#Apply a modified yaml file scaling from 10 to 20 replicas.
diff deployment.yaml deployment.20replicas.yaml
kubectl apply -f deployment.20replicas.yaml


#Check the status of the deployment
kubectl get deployment hello-world


#Check out the events...the replicaset is scaled to 20
kubectl describe deployment 


#Clean up from our demos
kubectl delete deployment hello-world
kubectl delete service hello-world



##########################################################
#################### DaemonSet ###########################
##########################################################

ssh aen@c1-cp1
cd ~/content/course/04/demos


#Demo 1 - Creating a DaemonSet on All Nodes
#We get one Pod per Node to run network services on that Node
kubectl get nodes
kubectl get daemonsets --namespace kube-system kube-proxy


#Let's create a DaemonSet with Pods on each node in our cluster...that's NOT the Control Plane Node
kubectl apply -f DaemonSet.yaml


#So we'll get three since we have 3 workers and 1 Control Plane Node in our cluster and the Control Plane Node is set to run only system pods
kubectl get daemonsets
kubectl get daemonsets -o wide
kubectl get pods -o wide


#Callout, labels, Desired/Current Nodes Scheduled. Pod Status and Template and Events.
kubectl describe daemonsets hello-world | more 


#Each Pods is created with our label, app=hello-world, controller-revision-hash and a pod-template-generation
kubectl get pods --show-labels


#If we change the label to one of our Pods...
MYPOD=$(kubectl get pods -l app=hello-world-app | grep hello-world | head -n 1 | awk {'print $1'})
echo $MYPOD
kubectl label pods $MYPOD app=not-hello-world --overwrite


#We'll get a new Pod from the DaemonSet Controller
kubectl get pods --show-labels

#Let's clean up this DaemonSet
kubectl delete daemonsets hello-world-ds
kubectl delete pods $MYPOD



#Demo 2 - Creating a DaemonSet on a Subset of Nodes
#Let's create a DaemonSet with a defined nodeSelector
kubectl apply -f DaemonSetWithNodeSelector.yaml


#No pods created because we don't have any nodes with the appropriate label
kubectl get daemonsets


#We need a Node that satisfies the Node Selector
kubectl label node c1-node1 node=hello-world-ns


#Let's see if a Pod gets created...
kubectl get daemonsets
kubectl get daemonsets -o wide
kubectl get pods -o wide

#What's going to happen if we remove the label
kubectl label node c1-node1 node-


#It's going to terminate the Pod, examine events, Desired Number of Nodes Scheduled...
kubectl describe daemonsets hello-world-ds


#Clean up our demo
kubectl delete daemonsets hello-world-ds



#Demo 3 - Updating a DaemonSet
#Deploy our v1 DaemonSet again
kubectl apply -f DaemonSet.yaml


#Check out our image version, 1.0
kubectl describe daemonsets hello-world


#Examine what our update stategy is...defaults to rollingUpdate and maxUnavailable 1
kubectl get DaemonSet hello-world-ds -o yaml | more


#Update our container image from 1.0 to 2.0 and apply the config
diff DaemonSet.yaml DaemonSet-v2.yaml
kubectl apply -f DaemonSet-v2.yaml


#Check on the status of our rollout, a touch slower than a deployment due to maxUnavailable.
kubectl rollout status daemonsets hello-world-ds


#We can see our DaemonSet Container Image is now 2.0 and in the Events that it rolled out.
kubectl describe daemonsets

#we can see the new controller-revision-hash and also an updated pod-template-generation
kubectl get pods --show-labels


#Time to clean up our demos
kubectl delete daemonsets hello-world-ds



##########################################################
#################### JobsCronJobs ########################
##########################################################

ssh aen@c1-cp1
cd ~/content/course/04/demos/

#Demo 1 - Executing tasks with Jobs, check out the file job.yaml
#Ensure you define a restartPolicy, the default of a Pod is Always, which is not compatible with a Job.
#We'll need OnFailure or Never, let's look at OnFailure
kubectl apply -f job.yaml


#Follow job status with a watch
kubectl get job --watch


#Get the list of Pods, status is Completed and Ready is 0/1
kubectl get pods


#Let's get some more details about the job...labels and selectors, Start Time, Duration and Pod Statuses
kubectl describe job hello-world-job


#Get the logs from stdout from the Job Pod
kubectl get pods -l job-name=hello-world-job 
kubectl logs PASTE_POD_NAME_HERE


#Our Job is completed, but it's up to use to delete the Pod or the Job.
kubectl delete job hello-world-job


#Which will also delete it's Pods
kubectl get pods




#Demo 2 - Show restartPolicy in action..., check out backoffLimit: 2 and restartPolicy: Never
#We'll want to use Never so our pods aren't deleted after backoffLimit is reached.
kubectl apply -f job-failure-OnFailure.yaml


#Let's look at the pods, enters a backoffloop after 2 crashes
kubectl get pods --watch


#The pods aren't deleted so we can troubleshoot here if needed.
kubectl get pods 


#And the job won't have any completions and it doesn't get deleted
kubectl get jobs 

#So let's review what the job did...Events, created...then deleted. Pods status, 3 Failed.
kubectl describe jobs | more


#Clean up this job
kubectl delete jobs hello-world-job-fail
kubectl get pods



#Demo 3 - Defining a Parallel Job
kubectl apply -f ParallelJob.yaml


#10 Pods will run in parallel up until 50 completions
kubectl get pods




#We can 'watch' the Statuses with watch
watch 'kubectl describe job | head -n 11'


#We'll get to 50 completions very quickly
kubectl get jobs


#Let's clean up...
kubectl delete job hello-world-job-parallel




#Demo 5 - Scheduling tasks with CronJobs
kubectl apply -f CronJob.yaml


#Quick overview of the job and it's schedule
kubectl get cronjobs


#But let's look closer...schedule, Concurrency, Suspend,Starting Deadline Seconds, events...there's execution history
kubectl describe cronjobs | more 


#Get a overview again...
kubectl get cronjobs


#The pods will stick around, in the event we need their logs or other inforamtion. How long?
kubectl get pods --watch


#They will stick around for successfulJobsHistoryLimit, which defaults to three
kubectl get cronjobs -o yaml


#Clean up the job...
kubectl delete cronjob hello-world-cron


#Deletes all the Pods too...
kubectl get pods 



##########################################################
#################### StaticProvisioning ##################
##########################################################

ssh aen@c1-cp1
cd ~/content/course/02/demos/


#Demo 0 - NFS Server Overview
ssh aen@c1-storage


#More details available here: https://help.ubuntu.com/lts/serverguide/network-file-system.html
#Install NFS Server and create the directory for our exports
sudo apt install nfs-kernel-server
sudo mkdir /export
sudo mkdir /export/volumes
sudo mkdir /export/volumes/pod


#Configure our NFS Export in /etc/export for /export/volumes. Using no_root_squash and no_subtree_check to 
#allow applications to mount subdirectories of the export directly.
sudo bash -c 'echo "/export/volumes  *(rw,no_root_squash,no_subtree_check)" > /etc/exports'
cat /etc/exports
sudo systemctl restart nfs-kernel-server.service
exit


#On each Node in your cluster...install the NFS client.
sudo apt install nfs-common -y 


#On one of the Nodes, test out basic NFS access before moving on.
ssh aen@c1-node1
sudo mount -t nfs4 c1-storage:/export/volumes /mnt/
mount | grep nfs
sudo umount /mnt
exit



#Demo 1 - Static Provisioning Persistent Volumes
#Create a PV with the read/write many and retain as the reclaim policy
kubectl apply -f nfs.pv.yaml


#Review the created resources, Status, Access Mode and Reclaim policy is set to Reclaim rather than Delete. 
kubectl get PersistentVolume pv-nfs-data


#Look more closely at the PV and it's configuration
kubectl describe PersistentVolume pv-nfs-data


#Create a PVC on that PV
kubectl apply -f nfs.pvc.yaml


#Check the status, now it's Bound due to the PVC on the PV. See the claim...
kubectl get PersistentVolume


#Check the status, Bound.
#We defined the PVC it statically provisioned the PV...but it's not mounted yet.
kubectl get PersistentVolumeClaim pvc-nfs-data
kubectl describe PersistentVolumeClaim pvc-nfs-data


#Let's create some content on our storage server
ssh aen@c1-storage
sudo bash -c 'echo "Hello from our NFS mount!!!" > /export/volumes/pod/demo.html'
more /export/volumes/pod/demo.html
exit


#Let's create a Pod (in a Deployment and add a Service) with a PVC on pvc-nfs-data
kubectl apply -f nfs.nginx.yaml
kubectl get service nginx-nfs-service
SERVICEIP=$(kubectl get service | grep nginx-nfs-service | awk '{ print $3 }')


#Check to see if our pods are Running before proceeding
kubectl get pods


#Let's access that application to see our application data...
curl http://$SERVICEIP/web-app/demo.html


#Check the Mounted By output for which Pod(s) are accessing this storage
kubectl describe PersistentVolumeClaim pvc-nfs-data
 

#If we go 'inside' the Pod/Container, let's look at where the PV is mounted
kubectl exec -it nginx-nfs-deployment-[tab][tab] -- /bin/bash
ls /usr/share/nginx/html/web-app
more /usr/share/nginx/html/web-app/demo.html
exit


#What node is this pod on?
kubectl get pods -o wide


#Let's log into that node and look at the mounted volumes...it's the kubelets job to make the device/mount available.
ssh c1-node[X]
mount | grep nfs
exit


#Let's delete the pod and see if we still have access to our data in our PV...
kubectl get pods
kubectl delete pods nginx-nfs-deployment-[tab][tab]


#We get a new pod...but is our app data still there???
kubectl get pods


#Let's access that application to see our application data...yes!
curl http://$SERVICEIP/web-app/demo.html




#Demo 2 - Controlling PV access with Access Modes and persistentVolumeReclaimPolicy
#scale up the deployment to 4 replicas
kubectl scale deployment nginx-nfs-deployment --replicas=4


#Now let's look at who's attached to the pvc, all 4 Pods
#Our AccessMode for this PV and PVC is RWX ReadWriteMany
kubectl describe PersistentVolumeClaim 


#Now when we access our application we're getting load balanced across all the pods hitting the same PV data
curl http://$SERVICEIP/web-app/demo.html


#Let's delete our deployment
kubectl delete deployment nginx-nfs-deployment


#Check status, still bound on the PV...why is that...
kubectl get PersistentVolume 


#Because the PVC still exists...
kubectl get PersistentVolumeClaim


#Can re-use the same PVC and PV from a Pod definition...yes! Because I didn't delete the PVC.
kubectl apply -f nfs.nginx.yaml


#Our app is up and running
kubectl get pods 


#But if I delete the deployment
kubectl delete deployment nginx-nfs-deployment


#AND I delete the PersistentVolumeClaim
kubectl delete PersistentVolumeClaim pvc-nfs-data


#My status is now Released...which means no one can claim this PV
kubectl get PersistentVolume


#But let's try to use it and see what happend, recreate the PVC for this PV
kubectl apply -f nfs.pvc.yaml


#Then try to use the PVC/PV in a Pod definition
kubectl apply -f nfs.nginx.yaml


#My pod creation is Pending
kubectl get pods


#As is my PVC Status...Pending...because that PV is Released and our Reclaim Policy is Retain
kubectl get PersistentVolumeClaim
kubectl get PersistentVolume


#Need to delete the PV if we want to 'reuse' that exact PV...to 're-create' the PV
kubectl delete deployment nginx-nfs-deployment
kubectl delete pvc pvc-nfs-data
kubectl delete pv pv-nfs-data


#If we recreate the PV, PVC, and the pods. we'll be able to re-deploy. 
#The clean up of the data is defined by the reclaim policy. (Delete will clean up for you, useful in dynamic provisioning scenarios)
#But in this case, since it's NFS, we have to clean it up and remove the files
#Nothing will prevent a user from getting this acess to this data, so it's imperitive to clean up. 
kubectl apply -f nfs.pv.yaml
kubectl apply -f nfs.pvc.yaml
kubectl apply -f nfs.nginx.yaml
kubectl get pods 


#Time to clean up for the next demo
kubectl delete -f nfs.nginx.yaml
kubectl delete pvc pvc-nfs-data
kubectl delete pv pv-nfs-data


##########################################################
#################### DynamicProvisioning #################
##########################################################

ssh aen@c1-cp1
cd ~/content/course/02/demos/

#Demo 0 - Azure Setup
#If you don't have your Azure Kubernetes Service Cluster available follow the script in CreateAKSCluster.sh


#Switch to our Azure cluster context
kubectl config use-context 'CSCluster'
kubectl get nodes 



#Demo 1 - StorageClasses and Dynamic Provisioning in the Azure
#Let's create a disk in Azure. Using a dynamic provisioner and storage class

#Check out our list of available storage classes, which one is default? Notice the Provisioner, Parameters and ReclaimPolicy.
kubectl get StorageClass
kubectl describe StorageClass default
kubectl describe StorageClass managed-premium


#let's create a Deployment of an nginx pod with a ReadWriteOnce disk, 
#we create a PVC and a Deployment that creates Pods that use that PVC
kubectl apply -f AzureDisk.yaml


#Check out the Access Mode, Reclaim Policy, Status, Claim and StorageClass
kubectl get PersistentVolume 


#Check out the Access Mode on the PersistentVolumeClaim, status is Bound and it's Volume is the PV dynamically provisioned
kubectl get PersistentVolumeClaim


#Let's see if our single pod was created (the Status can take a second to transition to Running)
kubectl get pods


#Clean up when we're finished.
kubectl delete deployment nginx-azdisk-deployment
kubectl delete PersistentVolumeClaim pvc-azure-managed




#Demo 2 - Defining a custom StorageClass in Azure
kubectl apply -f CustomStorageClass.yaml


#Get a list of the current StorageClasses kubectl get StorageClass.
kubectl get StorageClass

#A closer look at the SC, you can see the Reclaim Policy is Delete since we didn't set it in our StorageClass yaml
kubectl describe StorageClass managed-standard-ssd


#Let's use our new StorageClass
kubectl apply -f AzureDiskCustomStorageClass.yaml


#And take a closer look at our new Storage Class, Reclaim Policy Delete
kubectl get PersistentVolumeClaim
kubectl get PersistentVolume


#Clean up our demo resources
kubectl delete deployment nginx-azdisk-deployment-standard-ssd
kubectl delete PersistentVolumeClaim pvc-azure-standard-ssd
kubectl delete StorageClass managed-standard-ssd


#Switch back to our local cluster from Azure
kubectl config use-context kubernetes-admin@kubernetes


##########################################################
#################### Create AKSCluster ###################
##########################################################

# This demo will be run from c1-cp1 since kubectl is already installed there.
# This can be run from any system that has the Azure CLI client installed.

#Ensure Azure CLI command line utilitles are installed
#https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-apt?view=azure-cli-latest
AZ_REPO=$(lsb_release -cs)
echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | sudo tee /etc/apt/sources.list.d/azure-cli.list

curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null

sudo apt-get update
sudo apt-get install azure-cli

#Log into our subscription
az login
az account set --subscription "Demonstration Account"

#Create a resource group for the serivces we're going to create
az group create --name "Kubernetes-Cloud" --location centralus

#Let's get a list of the versions available to us, 
az aks get-versions --location centralus -o table

#let's check out some of the options available to us when creating our managed cluster
az aks create -h | more

#Let's create our AKS managed cluster. 
az aks create \
    --resource-group "Kubernetes-Cloud" \
    --generate-ssh-keys \
    --name CSCluster \
    --node-count 3 #default Node count is 3

#If needed, we can download and install kubectl on our local system.
az aks install-cli

#Get our cluster credentials and merge the configuration into our existing config file.
#This will allow us to connect to this system remotely using certificate based user authentication.
az aks get-credentials --resource-group "Kubernetes-Cloud" --name CSCluster

#List our currently available contexts
kubectl config get-contexts

#set our current context to the Azure context
kubectl config use-context CSCluster

#run a command to communicate with our cluster.
kubectl get nodes

#Get a list of running pods, we'll look at the system pods since we don't have anything running.
#Since the API Server is HTTP based...we can operate our cluster over the internet...esentially the same as if it was local using kubectl.
kubectl get pods --all-namespaces

#az aks delete --resource-group "Kubernetes-Cloud" --name CSCluster #--yes --no-wait


##########################################################
#################### Environmentvariables ################
##########################################################

#Log into the Control Plane Node to drive these demos.
ssh aen@c1-cp1
cd ~/content/course/03/demos


#Demo 1 - Passing Configuration into Containers using Environment Variables
#Create two deployments, one for a database system and the other our application.
#I'm putting a little wait in there so the Pods are created one after the other.
kubectl apply -f deployment-alpha.yaml
sleep 5
kubectl apply -f deployment-beta.yaml


#Let's look at the services
kubectl get service


#Now let's get the name of one of our pods
PODNAME=$(kubectl get pods | grep hello-world-alpha | awk '{print $1}' | head -n 1)
echo $PODNAME


#Inside the Pod, let's read the enviroment variables from our container
#Notice the alpha information is there but not the beta information. Since beta wasn't defined when the Pod started.
kubectl exec -it $PODNAME -- /bin/sh 
printenv | sort
exit


#If you delete the pod and it gets recreated, you will get the variables for the alpha and beta service information.
kubectl delete pod $PODNAME


#Get the new pod name and check the environment variables...the variables are define at Pod/Container startup.
PODNAME=$(kubectl get pods | grep hello-world-alpha | awk '{print $1}' | head -n 1)
kubectl exec -it $PODNAME -- /bin/sh -c "printenv | sort"


#If we delete our serivce and deployment 
kubectl delete deployment hello-world-beta
kubectl delete service hello-world-beta


#The enviroment variables stick around...to get a new set, the pod needs to be recreated.
kubectl exec -it $PODNAME -- /bin/sh -c "printenv | sort"



#Let's clean up after our demo
kubectl delete -f deployment-alpha.yaml



##########################################################
#################### Secrets #############################
##########################################################

#Log into the Control Plane Node to drive these demos.
ssh aen@c1-cp1
cd ~/content/course/03/demos


#Demo 1 - Creating and accessing Secrets
#Generic - Create a secret from a local file, directory or literal value
#They keys and values are case sensitive
kubectl create secret generic app1 \
    --from-literal=USERNAME=app1login \
    --from-literal=PASSWORD='S0methingS@Str0ng!'


#Opaque means it's an arbitrary user defined key/value pair. Data 2 means two key/value pairs in the secret.
#Other types include service accounts and container registry authentication info
kubectl get secrets


#app1 said it had 2 Data elements, let's look
kubectl describe secret app1


#If we need to access those at the command line...
#These are wrapped in bash expansion to add a newline to output for readability
echo $(kubectl get secret app1 --template={{.data.USERNAME}} )
echo $(kubectl get secret app1 --template={{.data.USERNAME}} | base64 --decode )

echo $(kubectl get secret app1 --template={{.data.PASSWORD}} )
echo $(kubectl get secret app1 --template={{.data.PASSWORD}} | base64 --decode )




#Demo 2 - Accessing Secrets inside a Pod
#As environment variables
kubectl apply -f deployment-secrets-env.yaml


PODNAME=$(kubectl get pods | grep hello-world-secrets-env | awk '{print $1}' | head -n 1)
echo $PODNAME


#Now let's get our enviroment variables from our container
kubectl exec -it $PODNAME -- /bin/sh
printenv | grep ^app1
exit


#Accessing Secrets as files
kubectl apply -f deployment-secrets-files.yaml


#Grab our pod name into a variable
PODNAME=$(kubectl get pods | grep hello-world-secrets-files | awk '{print $1}' | head -n 1)
echo $PODNAME


#Looking more closely at the Pod we see volumes, appconfig and in Mounts...
kubectl describe pod $PODNAME


#Let's access a shell on the Pod
kubectl exec -it $PODNAME -- /bin/sh


#Now we see the path we defined in the Volumes part of the Pod Spec
#A directory for each KEY and it's contents are the value
ls /etc/appconfig
cat /etc/appconfig/USERNAME
cat /etc/appconfig/PASSWORD
exit


#If you need to put only a subset of the keys in a secret check out this line here and look at items
#https://kubernetes.io/docs/concepts/storage/volumes#secret


#let's clean up after our demos...
kubectl delete secret app1
kubectl delete deployment hello-world-secrets-env
kubectl delete deployment hello-world-secrets-files




#Additional examples of using secrets in your Pods
#I'll leave this up to you to work with...
#Create a secret using clear text and the stringData field
kubectl apply -f secret.string.yaml


#Create a secret with encoded values, preferred over clear text.
echo -n 'app2login' | base64
echo -n 'S0methingS@Str0ng!' | base64
kubectl apply -f secret.encoded.yaml


#Check out the list of secrets now available 
kubectl get secrets

#examine how each object is stored, look at the annotations for the app2 secret.
kubectl get secrets app2 -o yaml
kubectl get secrets app3 -o yaml

#There's also an envFrom example in here for you too...
kubectl create secret generic app1 --from-literal=USERNAME=app1login --from-literal=PASSWORD='S0methingS@Str0ng!'


#Create the deployment, envFrom will create enviroment variables for each key in the named secret app1 with and set it's value set to the secrets value
kubectl apply -f deployment-secrets-env-from.yaml

PODNAME=$(kubectl get pods | grep hello-world-secrets-env-from | awk '{print $1}' | head -n 1)
echo $PODNAME 
kubectl exec -it $PODNAME -- /bin/sh
printenv | sort
exit


kubectl delete secret app1
kubectl delete secret app2
kubectl delete secret app3
kubectl delete deployment hello-world-secrets-env-from



##########################################################
#################### PrivateContainerRegistry ############
##########################################################

#Log into the Control Plane Node to drive these demos.
ssh aen@c1-cp1
cd ~/content/course/03/demos


#Demo 1 - Pulling a Container from a Private Container Registry


#To create a private repository in a container registry, follow the directions here
#https://docs.docker.com/docker-hub/repos/#private-repositories


#Let's pull down a hello-world image from our repo
sudo ctr images pull psk8s.azurecr.io/hello-app:1.0


#Let's get a listing of images from ctr to confim our image is downloaded
sudo ctr images list


#Tagging our image in the format your registry, image and tag
#You'll be using your own repository, so update that information here. 
#  source_ref: psk8s.azurecr.io/hello-app:1.0    #this is the image pulled from our repo
#  target_ref: docker.io/nocentino/hello-app:ps       #this is the image you want to push into your private repository
sudo ctr images tag psk8s.azurecr.io/hello-app:1.0 docker.io/nocentino/hello-app:ps


#Now push that locally tagged image into our private registry at docker hub
#You'll be using your own repository, so update that information here and specify your $USERNAME
#You will be prompted for the password to your repository
sudo ctr images push docker.io/nocentino/hello-app:ps --user $USERNAME


#Create our secret that we'll use for our image pull...
#Update the paramters to match the information for your repository including the servername, username, password and email.
kubectl create secret docker-registry private-reg-cred \
    --docker-server=https://index.docker.io/v2/ \
    --docker-username=$USERNAME \
    --docker-password=$PASSWORD \
    --docker-email=$EMAIL


#Ensure the image doesn't exist on any of our nodes...or else we can get a false positive since our image would be cached on the node
#Caution, this will delete *ANY* image that begins with hello-app
ssh aen@c1-node1 'sudo ctr --namespace k8s.io image ls "name~=hello-app" -q | sudo xargs ctr --namespace k8s.io image rm'
ssh aen@c1-node2 'sudo ctr --namespace k8s.io image ls "name~=hello-app" -q | sudo xargs ctr --namespace k8s.io image rm'
ssh aen@c1-node3 'sudo ctr --namespace k8s.io image ls "name~=hello-app" -q | sudo xargs ctr --namespace k8s.io image rm'


#Create a deployment using imagePullSecret in the Pod Spec.
kubectl apply -f deployment-private-registry.yaml


#Check out Containers and events section to ensure the container was actually pulled.
#This is why I made sure they were deleted from each Node above. 
kubectl describe pods hello-world


#Clean up after our demo, remove the images from c1-cp1.
kubectl delete -f deployment-private-registry.yaml
kubectl delete secret private-reg-cred
sudo ctr images remove docker.io/nocentino/hello-app:ps
sudo ctr images remove psk8s.azurecr.io/hello-app:1.0


##########################################################
#################### ConfigMaps ##########################
##########################################################

#Log into the Control Plane Node to drive these demos.
ssh aen@c1-cp1
cd ~/content/course/03/demos


#Demo 1 - Creating ConfigMaps
#Create a PROD ConfigMap
kubectl create configmap appconfigprod \
    --from-literal=DATABASE_SERVERNAME=sql.example.local \
    --from-literal=BACKEND_SERVERNAME=be.example.local


#Create a QA ConfigMap
#We can source our ConfigMap from files or from directories
#If no key, then the base name of the file
#Otherwise we can specify a key name to allow for more complex app configs and access to specific configuration elements
more appconfigqa
kubectl create configmap appconfigqa \
    --from-file=appconfigqa


#Each creation method yeilded a different structure in the ConfigMap
kubectl get configmap appconfigprod -o yaml
kubectl get configmap appconfigqa -o yaml




#Demo 2 - Using ConfigMaps in Pod Configurations
#First as environment variables
kubectl apply -f deployment-configmaps-env-prod.yaml


#Let's see or configured enviroment variables
PODNAME=$(kubectl get pods | grep hello-world-configmaps-env-prod | awk '{print $1}' | head -n 1)
echo $PODNAME


kubectl exec -it $PODNAME -- /bin/sh 
printenv | sort
exit


#Second as files
kubectl apply -f deployment-configmaps-files-qa.yaml


#Let's see our configmap exposed as a file using the key as the file name.
PODNAME=$(kubectl get pods | grep hello-world-configmaps-files-qa | awk '{print $1}' | head -n 1)
echo $PODNAME


kubectl exec -it $PODNAME -- /bin/sh 
ls /etc/appconfig
cat /etc/appconfig/appconfigqa
exit


#Our ConfigMap key, was the filename we read in, and the values are inside the file.
#This is how we can read in whole files at a time and present them to the file system with the same name in one ConfigMap
#So think about using this for daemon configs like nginx, redis...etc.
kubectl get configmap appconfigqa -o yaml


#Updating a configmap, change BACKEND_SERVERNAME to beqa1.example.local
kubectl edit configmap appconfigqa


kubectl exec -it $PODNAME -- /bin/sh 
watch cat /etc/appconfig/appconfigqa
exit



#Cleaning up our demo
kubectl delete deployment hello-world-configmaps-env-prod
kubectl delete deployment hello-world-configmaps-files-qa
kubectl delete configmap appconfigprod
kubectl delete configmap appconfigqa


#Additional examples of using secrets in your Pods
#I'll leave this up to you to work with...


#0 - Reading from a directory, each file's basename will be a key in the ConfigMap...but you can define a key if needed
kubectl create configmap httpdconfigprod1 --from-file=./configs/

kubectl apply -f deployment-configmaps-directory-qa.yaml
PODNAME=$(kubectl get pods | grep hello-world-configmaps-directory-qa | awk '{print $1}' | head -n 1)
echo $PODNAME

kubectl exec -it $PODNAME -- /bin/sh 
ls /etc/httpd
cat /etc/httpd/httpd.conf
cat /etc/httpd/ssl.conf
exit



#1. Defining a custom key for a file. All configuration will be under that key in the filesystem.
kubectl create configmap appconfigprod1 --from-file=app1=appconfigprod
kubectl describe configmap appconfigprod1
kubectl apply -f deployment-configmaps-files-key-qa.yaml
PODNAME=$(kubectl get pods | grep hello-world-configmaps-files-key-qa | awk '{print $1}' | head -n 1)
echo $PODNAME

kubectl exec -it $PODNAME -- /bin/sh 
ls /etc/appconfig
ls /etc/appconfig/app1
cat /etc/appconfig/app1
exit



#Clean up after our demos
kubectl delete deployments hello-world-configmaps-files-key-qa
kubectl delete deployments hello-world-configmaps-directory-qa
kubectl delete configmap httpdconfigprod1
kubectl delete configmap appconfigprod1



##########################################################
#################### SchedulerEvents #####################
##########################################################


#Log into the Control Plane Node to drive these demos.
ssh aen@c1-cp1
cd ~/content/course/04/demos



#Demo 1 - Finding scheduling information
#Let's create a deployment with three replicas
kubectl apply -f deployment.yaml


#Pods spread out evenly across the Nodes due to our scoring functions for selector spread during Scoring.
kubectl get pods -o wide


#We can look at the Pods events to see the scheduler making its choice
kubectl describe pods 


#If we scale our deployment to 6...
kubectl scale deployment hello-world --replicas=6


#We can see that the scheduler works to keep load even across the nodes.
kubectl get pods -o wide


#We can see the nodeName populated for this node
kubectl get pods hello-world-[tab][tab] -o yaml


#Clean up this demo...and delete its resources
kubectl delete deployment hello-world




#Demo 2 - Scheduling Pods with resource requests. Start a watch, the pods will go from Pending->ContainerCreating->Running
#Each pod has a 1 core CPU request.
kubectl get pods --watch &
kubectl apply -f requests.yaml


#We created three pods, one on each node
kubectl get pods -o wide


#Let's scale our deployment to 6 replica.  These pods will stay pending.  Some pod names may be repeated.
kubectl scale deployment hello-world-requests --replicas=6


#We see that three Pods are pending...why?
kubectl get pods -o wide
kubectl get pods -o wide | grep Pending


#Let's look at why the Pod is Pending...check out the Pod's events...
kubectl describe pods


#Now let's look at the node's Allocations...we've allocated 62% of our CPU...
#1 User pod using 1 whole CPU, one system Pod using 250 millicores of a CPU and 
#looking at allocatable resources, we have only 2 whole Cores available for use.
#The next pod coming along wants 1 whole core, and tha'ts not available.
#The scheduler can't find a place in this cluster to place our workload...is this good or bad?
kubectl describe node c1-node1

#Clean up after this demo
kubectl delete deployment hello-world-requests

#stop the watch
fg
ctrl+c

##########################################################
#################### Scheduling ##########################
##########################################################

#Log into the Control Plane Node to drive these demos.
ssh aen@c1-cp1
cd ~/content/course/04/demos

#Demo - Using Labels to Schedule Pods to Nodes
#The code is below to experiment with on your own. 
# Course: Managing the Kubernetes API Server and Pods
# Module: Managing Objects with Labels, Annotations, and Namespaces
# Clip:   Demo: Services, Labels, Selectors, and Scheduling Pods to Nodes




#Demo 1a - Using Affinity and Anti-Affinity to schedule Pods to Nodes
#Let's start off with a deployment of web and cache pods
#Affinity: we want to have always have a cache pod co-located on a Node where we a Web Pod
kubectl apply -f deployment-affinity.yaml


#Let's check out the labels on the nodes, look for kubernetes.io/hostname which
#we're using for our topologykey
kubectl describe nodes c1-node1 | head
kubectl get nodes --show-labels


#We can see that web and cache are both on the name node
kubectl get pods -o wide 


#If we scale the web deployment
#We'll still get spread across nodes in the ReplicaSet, so we don't need to enforce that with affinity
kubectl scale deployment hello-world-web --replicas=2
kubectl get pods -o wide 


#Then when we scale the cache deployment, it will get scheduled to the same node as the other web server
kubectl scale deployment hello-world-cache --replicas=2
kubectl get pods -o wide 


#Clean up the resources from these deployments
kubectl delete -f deployment-affinity.yaml




#Demo 1b - Using anti-affinity 
#Now, let's test out anti-affinity, deploy web and cache again. 
#But this time we're going to make sure that no more than 1 web pod is on each node with anti-affinity
kubectl apply -f deployment-antiaffinity.yaml
kubectl get pods -o wide


#Now let's scale the replicas in the web and cache deployments
kubectl scale deployment hello-world-web --replicas=4


#One Pod will go Pending because we can have only 1 Web Pod per node 
#when using requiredDuringSchedulingIgnoredDuringExecution in our antiaffinity rule
kubectl get pods -o wide --selector app=hello-world-web


#To 'fix' this we can change the scheduling rule to preferredDuringSchedulingIgnoredDuringExecution
#Also going to set the number of replicas to 4
kubectl apply -f deployment-antiaffinity-corrected.yaml
kubectl scale deployment hello-world-web --replicas=4


#Now we'll have 4 pods up an running, but doesn't the scheduler already ensure replicaset spread? Yes!
kubectl get pods -o wide --selector app=hello-world-web


#Let's clean up the resources from this demos
kubectl delete -f deployment-antiaffinity-corrected.yaml




#Demo 2 - Controlling Pods placement with Taints and Tolerations
#Let's add a Taint to c1-node1
kubectl taint nodes c1-node1 key=MyTaint:NoSchedule


#We can see the taint at the node level, look at the Taints section
kubectl describe node c1-node1


#Let's create a deployment with three replicas
kubectl apply -f deployment.yaml


#We can see Pods get placed on the non tainted nodes
kubectl get pods -o wide


#But we we add a deployment with a Toleration...
kubectl apply -f deployment-tolerations.yaml


#We can see Pods get placed on the non tainted nodes
kubectl get pods -o wide


#Remove our Taint
kubectl taint nodes c1-node1 key:NoSchedule-


#Clean up after our demo
kubectl delete -f deployment-tolerations.yaml
kubectl delete -f deployment.yaml




#Demo - Using Labels to Schedule Pods to Nodes
#From: 
# Course: Managing the Kubernetes API Server and Pods
# Module: Managing Objects with Labels, Annotations, and Namespaces
# Clip:   Demo: Services, Labels, Selectors, and Scheduling Pods to Nodes


#Scheduling a pod to a node
kubectl get nodes --show-labels 


#Label our nodes with something descriptive
kubectl label node c1-node2 disk=local_ssd
kubectl label node c1-node3 hardware=local_gpu


#Query our labels to confirm.
kubectl get node -L disk,hardware


#Create three Pods, two using nodeSelector, one without.
kubectl apply -f DeploymentsToNodes.yaml


#View the scheduling of the pods in the cluster.
kubectl get node -L disk,hardware
kubectl get pods -o wide


#If we scale this Deployment, all new Pods will go onto the node with the GPU label
kubectl scale deployment hello-world-gpu --replicas=3 
kubectl get pods -o wide 


#If we scale this Deployment, all new Pods will go onto the node with the SSD label
kubectl scale deployment hello-world-ssd --replicas=3 
kubectl get pods -o wide 


#If we scale this Deployment, all new Pods will go onto the node without the labels to keep the load balanced
kubectl scale deployment hello-world --replicas=3
kubectl get pods -o wide 


#If we go beyond that...it will use all node to keep load even globally
kubectl scale deployment hello-world --replicas=10
kubectl get pods -o wide 


#Clean up when we're finished, delete our labels and Pods
kubectl label node c1-node2 disk-
kubectl label node c1-node3 hardware-
kubectl delete deployments.apps hello-world
kubectl delete deployments.apps hello-world-gpu
kubectl delete deployments.apps hello-world-ssd


##########################################################
#################### NodeCordoning #######################
##########################################################

#Log into the Control Plane Node to drive these demos.
ssh aen@c1-cp1
cd ~/content/course/04/demos




#Demo 1 - Node Cordoning
#Let's create a deployment with three replicas
kubectl apply -f deployment.yaml


#Pods spread out evenly across the nodes
kubectl get pods -o wide


#Let's cordon c1-node3
kubectl cordon c1-node3


#That won't evict any pods...
kubectl get pods -o wide


#But if I scale the deployment
kubectl scale deployment hello-world --replicas=6


#c1-node3 won't get any new pods...one of the other Nodes will get an extra Pod here.
kubectl get pods -o wide


#Let's drain (remove) the Pods from c1-node3...
kubectl drain c1-node3 


#Let's try that again since daemonsets aren't scheduled we need to work around them.
kubectl drain c1-node3 --ignore-daemonsets


#Now all the workload is on c1-node1 and 2
kubectl get pods -o wide


#We can uncordon c1-node3, but nothing will get scheduled there until there's an event like a scaling operation or an eviction.
#Something that will cause pods to get created
kubectl uncordon c1-node3


#So let's scale that Deployment and see where they get scheduled...
kubectl scale deployment hello-world --replicas=9


#All three get scheduled to the cordoned node
kubectl get pods -o wide


#Clean up this demo...
kubectl delete deployment hello-world




#Demo 2 - Manually scheduling a Pod by specifying nodeName
kubectl apply -f pod.yaml


#Our Pod should be on c1-node3
kubectl get pod -o wide


#Let's delete our pod, since there's no controller it won't get recreated :(
kubectl delete pod hello-world-pod 


#Now let's cordon node3 again
kubectl cordon c1-node3


#And try to recreate our pod
kubectl apply -f pod.yaml


#You can still place a pod on the node since the Pod isn't getting 'scheduled', status is SchedulingDisabled
kubectl get pod -o wide


#Can't remove the unmanaged Pod either since it's not managed by a Controller and won't get restarted
kubectl drain c1-node3 --ignore-daemonsets 


#Let's clean up our demo, delete our pod and uncordon the node
kubectl delete pod hello-world-pod 
 

#Now let's uncordon node3 so it's able to have pods scheduled to it
#I forgot to do this in the video demo :)
kubectl uncordon c1-node3


##########################################################
#################### Invetigating Networking #############
##########################################################


#1 - Investigating Kubernetes Networking
#Log into our local cluster
ssh aen@c1-cp1
cd ~/content/course/02/demos



#Local Cluster - Calico CNI Plugin
#Get all Nodes and their IP information, INTERNAL-IP is the real IP of the Node
kubectl get nodes -o wide


#Let's deploy a basic workload, hello-world with 3 replicas to create some pods on the pod network.
kubectl apply -f Deployment.yaml


#Get all Pods, we can see each Pod has a unique IP on the Pod Network.
#Our Pod Network was defined in the first course and we chose 192.168.0.0/16
kubectl get pods -o wide


#Let's hop inside a pod and check out it's networking, a single interface an IP on the Pod Network
#The line below will get a list of pods from the label query and return the name of the first pod in the list
PODNAME=$(kubectl get pods --selector=app=hello-world -o jsonpath='{ .items[0].metadata.name }')
echo $PODNAME
kubectl exec -it $PODNAME -- /bin/sh
ip addr
exit


#For the Pod on c1-node1, let's find out how traffic gets from c1-cp1 to c1-node1 to get to that Pod.

#Look at the annotations, specifically the annotation projectcalico.org/IPv4IPIPTunnelAddr: 192.168.19.64...your IP may vary
#Check out the Addresses: InternalIP, that's the real IP of the Node.
# Pod IPs are allocated from the network Pod Network which is configurable in Calico, it's controlling the IP allocation.
# Calico is using a tunnel interfaces to implement the Pod Network model. 
# Traffic going to other Pods will be sent into the tunnel interface and directly to the Node running the Pod.
# For more info on Calico's operations https://docs.projectcalico.org/reference/cni-plugin/configuration
kubectl describe node c1-cp1 | more


#Let's see how the traffic gets to c1-node1 from c1-cp1
#Via routes on the node, to get to c1-node1 traffic goes into tunl0/192.168.19.64...your IP may vary
#Calico handles the tunneling and sends the packet to the correct node to be send on into the Pod running on that Node based on the defined routes
#Follow each route, showing how to get to the Pod IP, it will need to go to the tun0 interface.
#There cali* interfaces are for each Pod on the Pod network, traffic destined for the Pod IP will have a 255.255.255.255 route to this interface.
kubectl get pods -o wide
route


#The local tunl0 is 192.168.19.64, packets destined for Pods running on c1-cp1 will be routed to this interface and get encapsulated
#Then send to the destination node for de-encapsulation.
ip addr


#Log into c1-node1 and look at the interfaces, there's tunl0 192.168.222.192...this is this node's tunnel interface
ssh aen@c1-node1


#This tunl0 is the destination interface, on this Node its 192.168.222.192, which we saw on the route listing on c1-cp1
ip addr


#All Nodes will have routes back to the other Nodes via the tunl0 interface
route


#Exit back to c1-cp1
exit







#Azure Kubernetes Service - kubenet
#Get all Nodes and their IP information, INTERNAL-IP is the real IP of the Node
kubectl config use-context 'CSCluster'


#Let's deploy a basic workload, hello-world with 3 replicas.
kubectl apply -f Deployment.yaml

#Note the INTERNAL-IP, these are on the virtual network in Azure, the real IPs of the underlying VMs
kubectl get nodes -o wide


#This time we're using a different network plugin, kubenet. It's based on routes/bridges rather than tunnels. Let's explore
#Check out Addresses and PodCIDR
kubectl describe nodes | more


#The Pods are getting IPs from their Node's PodCIDR Range
kubectl get pods -o wide


#Access an AKS Node via SSH so we can examine it's network config which uses kubenet
#https://docs.microsoft.com/en-us/azure/aks/ssh#configure-virtual-machine-scale-set-based-aks-clusters-for-ssh-access
NODENAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl debug node/$NODENAME -it --image=mcr.microsoft.com/aks/fundamental/base-ubuntu:v0.0.11


#Check out the routes, notice the route to the local Pod Network matching PodCIDR for this Node sending traffic to cbr0
#The routes for the other PodCIDR ranges on the other Nodes are implemented in the cloud's virtual network. 
route


#In Azure, these routes are implemented as route tables assigned to the virtual machine's for your Nodes.
#You'll find the routes implemented in the Resource Group as a Route Table assigned to the subnet the Nodes are on.
#This is a link to my Azure account, your's will vary.
#https://portal.azure.com/#@nocentinohotmail.onmicrosoft.com/resource/subscriptions/fd0c5e48-eea6-4b37-a076-0e23e0df74cb/resourceGroups/mc_kubernetes-cloud_cscluster_centralus/providers/Microsoft.Network/routeTables/aks-agentpool-89481420-routetable/overview

#Check out the eth0, actual Node interface IP, then cbr0 which is the bridge the Pods are attached to and 
#has an IP on the Pod Network.
#Each Pod has an veth interface on the bridge, which you see here, and and interface inside the container
#which will have the Pod IP.
ip addr 


#Let's check out the bridge's 'connections'
brctl show


#Exit the container on the node
exit


#Here is the Pod's interface and it's IP. 
#This interface is attached to the cbr0 bridge on the Node to get access to the Pod network. 
PODNAME=$(kubectl get pods -o jsonpath='{ .items[0].metadata.name }')
kubectl exec -it $PODNAME -- ip addr


#And inside the pod, there's a default route in the pod to the interface 10.244.0.1 which is the brige interface cbr0.
#Then the Node will route it on the Node network for reachability to other nodes.
kubectl exec -it $PODNAME -- route


#Delete the deployment in AKS, switch to the local cluster and delete the deployment too. 
kubectl delete -f Deployment.yaml 
kubectl config use-context kubernetes-admin@kubernetes
kubectl delete -f Deployment.yaml 



##########################################################
#################### sshAKSCluster #######################
##########################################################

#https://docs.microsoft.com/en-us/azure/aks/ssh#configure-virtual-machine-scale-set-based-aks-clusters-for-ssh-access

##########
###UPDATE:
###You no longer have to perform these many steps to get SSH access to a node in AKS, follow the directions in the link above.  
##########


#CLUSTER_RESOURCE_GROUP=$(az aks show --resource-group Kubernetes-Cloud --name CSCluster --query nodeResourceGroup -o tsv)
#SCALE_SET_NAME=$(az vmss list --resource-group $CLUSTER_RESOURCE_GROUP --query [0].name -o tsv)

#echo $CLUSTER_RESOURCE_GROUP
#echo $SCALE_SET_NAME

#az vmss extension set  \
#    --resource-group $CLUSTER_RESOURCE_GROUP \
#    --vmss-name $SCALE_SET_NAME \
#    --name VMAccessForLinux \
#    --publisher Microsoft.OSTCExtensions \
#    --version 1.4 \
#    --protected-settings "{\"username\":\"azureuser\", \"ssh_key\":\"$(cat ~/.ssh/id_rsa.pub)\"}"

#az vmss update-instances --instance-ids '*' \
#    --resource-group $CLUSTER_RESOURCE_GROUP \
#    --name $SCALE_SET_NAME

#kubectl run -it --rm aks-ssh --image=debian

#apt-get update && apt-get install openssh-client -y

#kubectl cp ~/.ssh/id_rsa $(kubectl get pod -l run=aks-ssh -o jsonpath='{.items[0].metadata.name}'):~/.ssh/id_rsa


#sudo apt-get install bridge-utils

#sudo brctl show


##########################################################
#################### ConfiguringDNS ######################
##########################################################

ssh aen@c1-cp1
cd ~/content/course/02/demos


#1. Investigating the Cluster DNS Service
#It's Deployed as a Service in the cluster with a Deployment in the kube-system namespace
kubectl get service --namespace kube-system


#Two Replicas, Args injecting the location of the config file which is backed by ConfigMap mounted as a Volume.
kubectl describe deployment coredns --namespace kube-system | more
 

#The configmap defining the CoreDNS configuration and we can see the default forwarder is /etc/resolv.conf
kubectl get configmaps --namespace kube-system coredns -o yaml | more




#2. Configuring CoreDNS to use custom Forwarders, spaces not tabs!
#Defaults use the nodes DNS Servers for fowarders
#Replaces forward . /etc/resolv.conf
#with forward . 1.1.1.1
#Add a conditional domain forwarder for a specific domain
#ConfigMap will take a second to update the mapped file and the config to be reloaded
kubectl apply -f CoreDNSConfigCustom.yaml --namespace kube-system


#How will we know when the CoreDNS configuration file is updated in the pod?
#You can tail the log looking for the reload the configuration file...this can take a minute or two
#Also look for any errors post configuration. Seeing [WARNING] No files matching import glob pattern: custom/*.override is normal.
kubectl logs --namespace kube-system --selector 'k8s-app=kube-dns' --follow 


#Run some DNS queries against the kube-dns service cluster ip to ensure everything works...
SERVICEIP=$(kubectl get service --namespace kube-system kube-dns -o jsonpath='{ .spec.clusterIP }')
nslookup www.pluralsight.com $SERVICEIP
nslookup www.centinosystems.com $SERVICEIP


#On c1-cp1, let's put the default configuration back, using . forward /etc/resolv.conf 
kubectl apply -f CoreDNSConfigDefault.yaml --namespace kube-system



#3. Configuring Pod DNS client Configuration
kubectl apply -f DeploymentCustomDns.yaml


#Let's check the DNS configuration of a Pod created with that configuration
#This line will grab the first pod matching the defined selector
PODNAME=$(kubectl get pods --selector=app=hello-world-customdns -o jsonpath='{ .items[0].metadata.name }')
echo $PODNAME
kubectl exec -it $PODNAME -- cat /etc/resolv.conf


#Clean up our resources
kubectl delete -f DeploymentCustomDns.yaml



#Demo 3 - let's get a pods DNS A record and a Services A record
#Create a deployment and a service
kubectl apply -f Deployment.yaml


#Get the pods and their IP addresses
kubectl get pods -o wide


#Get the address of our DNS Service again...just in case
SERVICEIP=$(kubectl get service --namespace kube-system kube-dns -o jsonpath='{ .spec.clusterIP }')


#For one of the pods replace the dots in the IP address with dashes for example 192.168.206.68 becomes 192-168-206-68
#We'll look at some additional examples of Service Discovery in the next module too.
nslookup 192-168-206-[XX].default.pod.cluster.local $SERVICEIP


#Our Services also get DNS A records
#There's more on service A records in the next demo
kubectl get service 
nslookup hello-world.default.svc.cluster.local $SERVICEIP


#Clean up our resources
kubectl delete -f Deployment.yaml


#TODO for the viewer...you can use this technique to verify your DNS forwarder configuration from the first demo in this file. 
#Recreate the custom configuration by applying the custom configmap defined in CoreDNSConfigCustom.yaml
#Logging in CoreDNS will log the query, but not which forwarder it was sent to. 
#We can use tcpdump to listen to the packets on the wire to see where the DNS queries are being sent to.


#Find the name of a Node running one of the DNS Pods running...so we're going to observe DNS queries there.
DNSPODNODENAME=$(kubectl get pods --namespace kube-system --selector=k8s-app=kube-dns -o jsonpath='{ .items[0].spec.nodeName }')
echo $DNSPODNODENAME


#Let's log into THAT node running the dns pod and start a tcpdump to watch our dns queries in action.
#Your interface (-i) name may be different
ssh aen@$DNSPODNODENAME
sudo tcpdump -i ens33 port 53 -n 


#In a second terminal, let's test our DNS configuration from a pod to make sure we're using the configured forwarder.
#When this pod starts, it will point to our cluster dns service.
#Install dnsutils for nslookup and dig
ssh aen@c1-cp1
kubectl run -it --rm debian --image=debian
apt-get update && apt-get install dnsutils -y


#In our debian pod let's look at the dns config and run two test DNS queries
#The nameserver will be your cluster dns service cluster ip.
#We'll query two domains to generate traffic for our tcpdump
cat /etc/resolv.conf
nslookup www.pluralsight.com
nslookup www.centinosystems.com


#Switch back to our second terminal and review the tcpdump, confirming each query is going to the correct forwarder
#Here is some example output...www.pluralsight.com is going to 1.1.1.1 and www.centinosystems.com is going to 9.9.9.9
#172.16.94.13.63841 > 1.1.1.1.53: 24753+ A? www.pluralsight.com. (37)
#172.16.94.13.42523 > 9.9.9.9.53: 29485+ [1au] A? www.centinosystems.com. (63)

#Exit the tcpdump
ctrl+c


#Log out of the node, back onto c1-cp1
exit


#Switch sessions and break out of our pod and it will be deleted.
exit


#Exit out of our second SSH session and get a shell back on c1-cp1
exit

##########################################################
#################### Services ############################
##########################################################

ssh aen@c1-cp1
cd ~/content/course/03/demos/

#1 - Exposing and accessing applications with Services on our local cluster
#ClusterIP

#Imperative, create a deployment with one replica
kubectl create deployment hello-world-clusterip \
    --image=psk8s.azurecr.io/hello-app:1.0


#When creating a service, you can define a type, if you don't define a type, the default is ClusterIP
kubectl expose deployment hello-world-clusterip \
    --port=80 --target-port=8080 --type ClusterIP


#Get a list of services, examine the Type, CLUSTER-IP and Port
kubectl get service


#Get the Service's ClusterIP and store that for reuse.
SERVICEIP=$(kubectl get service hello-world-clusterip -o jsonpath='{ .spec.clusterIP }')
echo $SERVICEIP


#Access the service inside the cluster
curl http://$SERVICEIP


#Get a listing of the endpoints for a service, we see the one pod endpoint registered.
kubectl get endpoints hello-world-clusterip
kubectl get pods -o wide


#Access the pod's application directly on the Target Port on the Pod, not the service's Port, useful for troubleshooting.
#Right now there's only one Pod and its one Endpoint
kubectl get endpoints hello-world-clusterip
PODIP=$(kubectl get endpoints hello-world-clusterip -o jsonpath='{ .subsets[].addresses[].ip }')
echo $PODIP
curl http://$PODIP:8080


#Scale the deployment, new endpoints are registered automatically
kubectl scale deployment hello-world-clusterip --replicas=6
kubectl get endpoints hello-world-clusterip


#Access the service inside the cluster, this time our requests will be load balanced...whooo!
curl http://$SERVICEIP


#The Service's Endpoints match the labels, let's look at the service and it's selector and the pods labels.
kubectl describe service hello-world-clusterip
kubectl get pods --show-labels


#Clean up these resources for the next demo
kubectl delete deployments hello-world-clusterip
kubectl delete service hello-world-clusterip




#2 - Creating a NodePort Service
#Imperative, create a deployment with one replica
kubectl create deployment hello-world-nodeport \
    --image=psk8s.azurecr.io/hello-app:1.0


#When creating a service, you can define a type, if you don't define a type, the default is ClusterIP
kubectl expose deployment hello-world-nodeport \
    --port=80 --target-port=8080 --type NodePort


#Let's check out the services details, there's the Node Port after the : in the Ports column. It's also got a ClusterIP and Port
#This NodePort service is available on that NodePort on each node in the cluster
kubectl get service


CLUSTERIP=$(kubectl get service hello-world-nodeport -o jsonpath='{ .spec.clusterIP }')
PORT=$(kubectl get service hello-world-nodeport -o jsonpath='{ .spec.ports[].port }')
NODEPORT=$(kubectl get service hello-world-nodeport -o jsonpath='{ .spec.ports[].nodePort }')

#Let's access the services on the Node Port...we can do that on each node in the cluster and 
#from outside the cluster...regardless of where the pod actually is

#We have only one pod online supporting our service
kubectl get pods -o wide


#And we can access the service by hitting the node port on ANY node in the cluster on the Node's Real IP or Name.
#This will forward to the cluster IP and get load balanced to a Pod. Even if there is only one Pod.
curl http://c1-cp1:$NODEPORT
curl http://c1-node1:$NODEPORT
curl http://c1-node2:$NODEPORT
curl http://c1-node3:$NODEPORT


#And a Node port service is also listening on a Cluster IP, in fact the Node Port traffic is routed to the ClusterIP
echo $CLUSTERIP:$PORT
curl http://$CLUSTERIP:$PORT


#Let's delete that service
kubectl delete service hello-world-nodeport
kubectl delete deployment hello-world-nodeport




#3 - Creating LoadBalancer Services in Azure or any cloud
#Switch contexts into AKS, we created this cluster together in 'Kubernetes Installation and Configuration Fundamentals'
#I've added a script to create a GKE and AKS cluster this course's downloads.
kubectl config use-context 'CSCluster'


#Let's create a deployment
kubectl create deployment hello-world-loadbalancer \
    --image=psk8s.azurecr.io/hello-app:1.0


#When creating a service, you can define a type, if you don't define a type, the default is ClusterIP
kubectl expose deployment hello-world-loadbalancer \
    --port=80 --target-port=8080 --type LoadBalancer


#Can take a minute for the load balancer to provision and get an public IP, you'll see EXTERNAL-IP as <pending>
kubectl get service


LOADBALANCERIP=$(kubectl get service hello-world-loadbalancer -o jsonpath='{ .status.loadBalancer.ingress[].ip }')
curl http://$LOADBALANCERIP:$PORT


#The loadbalancer, which is 'outside' your cluster, sends traffic to the NodePort Service which sends it to the ClusterIP to get to your pods!
#Your cloud load balancer will have health probes checking the health of the node port service on the real node IPs.
#This isn't the health of our application, that still needs to be configured via readiness/liveness probes and maintained by your Deployment configuration
kubectl get service hello-world-loadbalancer



#Clean up the resources from this demo
kubectl delete deployment hello-world-loadbalancer
kubectl delete service hello-world-loadbalancer


#Let's switch back to our local cluster
kubectl config use-context kubernetes-admin@kubernetes



#Declarative examples
kubectl config use-context kubernetes-admin@kubernetes
kubectl apply -f service-hello-world-clusterip.yaml
kubectl get service


#Creating a NodePort with a predefined port, first with a port outside of the NodePort range then a corrected one.
kubectl apply -f service-hello-world-nodeport-incorrect.yaml
kubectl apply -f service-hello-world-nodeport.yaml
kubectl get service


#Switch contexts to Azure to create a cloud load balancer
kubectl config use-context 'CSCluster'
kubectl apply -f service-hello-world-loadbalancer.yaml
kubectl get service


#Clean up these resources
kubectl delete -f service-hello-world-loadbalancer.yaml
kubectl config use-context kubernetes-admin@kubernetes
kubectl delete -f service-hello-world-nodeport.yaml
kubectl delete -f service-hello-world-clusterip.yaml



##########################################################
#################### ServicesDiscovery ###################
##########################################################

ssh aen@c1-cp1
cd ~/content/course/03/demos/


#Service Discovery
#Cluster DNS

#Let's create a deployment in the default namespace
kubectl create deployment hello-world-clusterip \
    --image=psk8s.azurecr.io/hello-app:1.0


#Let's create a deployment in the default namespace
kubectl expose deployment hello-world-clusterip \
    --port=80 --target-port=8080 --type ClusterIP


#We can use nslookup or dig to investigate the DNS record, it's CNAME @10.96.0.10 is the cluser IP of our DNS Server
kubectl get service kube-dns --namespace kube-system


#Each service gets a DNS record, we can use this in our applications to find services by name.
#The A record is in the form <servicename>.<namespace>.svc.<clusterdomain>
nslookup hello-world-clusterip.default.svc.cluster.local 10.96.0.10
kubectl get service hello-world-clusterip


#Create a namespace, deployment with one replica and a service
kubectl create namespace ns1


#Let's create a deployment with the same name as the first one, but in our new namespace
kubectl create deployment hello-world-clusterip --namespace ns1 \
    --image=psk8s.azurecr.io/hello-app:1.0


kubectl expose deployment hello-world-clusterip --namespace ns1 \
    --port=80 --target-port=8080 --type ClusterIP


#Let's check the DNS record for the service in the namespace, ns1. See how ns1 is in the DNS record?
#<servicename>.<namespace>.svc.<clusterdomain>
nslookup hello-world-clusterip.ns1.svc.cluster.local 10.96.0.10


#Our service in the default namespace is still there, these are completely unique services.
nslookup hello-world-clusterip.default.svc.cluster.local 10.96.0.10


#Get the environment variables for the pod in our default namespace
#More details about the lifecycle of variables in "Configuring and Managing Kubernetes Storage and Scheduling"
#Only the kubernetes service is available? Why? I created the deployment THEN I created the service
PODNAME=$(kubectl get pods -o jsonpath='{ .items[].metadata.name }')
echo $PODNAME
kubectl exec -it $PODNAME -- env | sort


#Environment variables are only created at pod start up, so let's delete the pod
kubectl delete pod $PODNAME


#And check the enviroment variables again...
PODNAME=$(kubectl get pods -o jsonpath='{ .items[].metadata.name }')
echo $PODNAME
kubectl exec -it $PODNAME -- env | sort


#ExternalName
kubectl apply -f service-externalname.yaml


#The record is in the form <servicename>.<namespace>.<clusterdomain>. You may get an error that says ** server can't find hello-world.api.example.com: NXDOMAIN this is ok.
nslookup hello-world-api.default.svc.cluster.local 10.96.0.10




#Let's clean up our resources in this demo
kubectl delete service hello-world-api
kubectl delete service hello-world-clusterip
kubectl delete service hello-world-clusterip --namespace ns1
kubectl delete deployment hello-world-clusterip
kubectl delete deployment hello-world-clusterip --namespace ns1
kubectl delete namespace ns1




##########################################################
#################### CreateAKSCluster ####################
##########################################################

# This demo will be run from c1-cp1 since kubectl is already installed there.
# This can be run from any system that has the Azure CLI client installed.

#Ensure Azure CLI command line utilitles are installed
#https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-apt?view=azure-cli-latest
AZ_REPO=$(lsb_release -cs)
echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | sudo tee /etc/apt/sources.list.d/azure-cli.list


#Install the gpg key for Microsoft's repository
curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null


sudo apt-get update
sudo apt-get install azure-cli


#Log into our subscription
#Free account - https://azure.microsoft.com/en-us/free/
az login
az account set --subscription "Demonstration Account"


#Create a resource group for the serivces we're going to create
az group create --name "Kubernetes-Cloud" --location centralus


#Let's get a list of the versions available to us
az aks get-versions --location centralus -o table


#Let's create our AKS managed cluster. Use --kubernetes-version to specify a version.
az aks create \
    --resource-group "Kubernetes-Cloud" \
    --generate-ssh-keys \
    --name CSCluster \
    --node-count 3 #default Node count is 3


#If needed, we can download and install kubectl on our local system.
az aks install-cli


#Get our cluster credentials and merge the configuration into our existing config file.
#This will allow us to connect to this system remotely using certificate based user authentication.
az aks get-credentials --resource-group "Kubernetes-Cloud" --name CSCluster


#List our currently available contexts
kubectl config get-contexts


#set our current context to the Azure context
kubectl config use-context CSCluster


#run a command to communicate with our cluster.
kubectl get nodes


#Get a list of running pods, we'll look at the system pods since we don't have anything running.
#Since the API Server is HTTP based...we can operate our cluster over the internet...esentially the same as if it was local using kubectl.
kubectl get pods --all-namespaces


#Let's set to the kubectl context back to our local custer
kubectl config use-context kubernetes-admin@kubernetes


#use kubectl get nodes
kubectl get nodes

#az aks delete --resource-group "Kubernetes-Cloud" --name CSCluster #--yes --no-wait



##########################################################
#################### CreateGKSCluster ####################
##########################################################

#Instructions from this URL: https://cloud.google.com/sdk/docs/quickstart-debian-ubuntu
# Create environment variable for correct distribution
CLOUD_SDK_REPO="cloud-sdk-$(lsb_release -c -s)"


# Add the Cloud SDK distribution URL as a package source
echo "deb http://packages.cloud.google.com/apt $CLOUD_SDK_REPO main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list


# Import the Google Cloud Platform public key
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -


# Update the package list and install the Cloud SDK
sudo apt-get update 
sudo apt-get install google-cloud-sdk


#Authenticate our console session with gcloud
gcloud init --console-only


#Create a named gcloud project
gcloud projects create psdemogke-1 --name="Kubernetes-Cloud"


#Set our current project context
gcloud config set project psdemogke-1


#You may have to adjust your resource limits and enabled billing here based on your subscription here.
#1. Go to https://console.cloud.google.com
#2. Ensure that you are in the project you just created, in the search bar type "Projects" and select the project we just created.
#3. From the Navigation menu on the top left, click Kubernetes Engine
#4. On the Kubernetes Engine landing page click "ENABLE BILLING" and select a billing account from the drop down list. Then click "Set Account" 
#       Then wait until the Kubernete API is enabled, this may take several minutes.


#Tell GKE to create a single zone, three node cluster for us. 3 is the default size.
#We're disabling basic authentication as it's no longer supported after 1.19 in GKE
#For more information on authentication check out this link here:
#   https://cloud.google.com/kubernetes-engine/docs/how-to/api-server-authentication#authenticating_users
gcloud container clusters create cscluster --region us-central1-a --no-enable-basic-auth


#Get our credentials for kubectl, this uses oath rather than certficates.
#See this link for more details on authentication to GKE Clusters
#   https://cloud.google.com/kubernetes-engine/docs/how-to/api-server-authentication#authenticating_users
gcloud container clusters get-credentials cscluster --zone us-central1-a --project psdemogke-1


#Check out out lists of kubectl contexts
kubectl config get-contexts


#set our current context to the GKE context, you may need to update this to your cluster context name.
kubectl config use-context gke_psdemogke-1_us-central1-a_cscluster


#run a command to communicate with our cluster.
kubectl get nodes


#Delete our GKE cluster
#gcloud container clusters delete cscluster --zone=us-central1-a 

#Delete our project.
#gcloud projects delete psdemogke-1


#Get a list of all contexts on this system.
kubectl config get-contexts


#Let's set to the kubectl context back to our local custer
kubectl config use-context kubernetes-admin@kubernetes


#use kubectl get nodes
kubectl get nodes


##########################################################
#################### ingress-nodeport ####################
##########################################################

ssh aen@c1-cp1
cd ~/content/course/04/demos/

#Check out 1-ingress-loadbalancer.sh for the cloud demos

#Demo 1 - Deploying an ingress controller
#For our Ingress Controller, we're going to go with nginx, widely available and easy to use. 
#Follow this link here to find a manifest for nginx Ingress Controller for various infrastructures, Cloud, Bare Metal, EKS and more.
#We have to choose a platform to deploy in...we can choose Cloud, Bare-metal (which we can use in our local cluster) and more.
https://kubernetes.github.io/ingress-nginx/deploy/


#Bare-metal: On our on prem cluster: Bare Metal (NodePort)
#Let's make sure we're in the right context and deploy the manifest for the Ingress Controller found in the link just above (around line 9).
kubectl config use-context kubernetes-admin@kubernetes
kubectl apply -f ./baremetal/deploy.yaml


#Using this manifest, the Ingress Controller is in the ingress-nginx namespace but 
#It will monitor for Ingresses in all namespaces by default. If can be scoped to monitor a specific namespace if needed.


#Check the status of the pods to see if the ingress controller is online.
kubectl get pods --namespace ingress-nginx


#Now let's check to see if the service is online. This of type NodePort, so do you have an EXTERNAL-IP?
kubectl get services --namespace ingress-nginx


#Check out the ingressclass nginx...we have not set the is-default-class so in each of our Ingresses we will need 
#specify an ingressclassname
kubectl describe ingressclasses nginx
#kubectl annotate ingressclasses nginx "ingressclass.kubernetes.io/is-default-class=true"


#Demo 2 - Single Service
#Create a deployment, scale it to 2 replicas and expose it as a serivce. 
#This service will be ClusterIP and we'll expose this service via the Ingress.
kubectl create deployment hello-world-service-single --image=psk8s.azurecr.io/hello-app:1.0
kubectl scale deployment hello-world-service-single --replicas=2
kubectl expose deployment hello-world-service-single --port=80 --target-port=8080 --type=ClusterIP



#Create a single Ingress routing to the one backend service on the service port 80 listening on all hostnames
kubectl apply -f ingress-single.yaml


#Get the status of the ingress. It's routing for all host names on that public IP on port 80
#This is a NodePort service so there's no public IP, its the NodePort Serivce that you'll use for access or integration into load balancing.
#If you don't define an ingressclassname and don't have a default ingress class the address won't be updated.
kubectl get ingress --watch #Wait for the Address to be populated before proceeding
kubectl get services --namespace ingress-nginx


#Notice the backends are the Service's Endpoints...so the traffic is going straight from the Ingress Controller to the Pod cutting out the kube-proxy hop.
#Also notice, the default back end is the same service, that's because we didn't define any rules and
#we just populated ingress.spec.backend. We're going to look at rules next...
kubectl describe ingress ingress-single


#Access the application via the exposed ingress that's listening the NodePort and it's static port, let's get some variables so we can reused them
INGRESSNODEPORTIP=$(kubectl get ingresses ingress-single -o jsonpath='{ .status.loadBalancer.ingress[].ip }')
NODEPORT=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{ .spec.ports[?(@.name=="http")].nodePort }')
echo $INGRESSNODEPORTIP:$NODEPORT
curl http://$INGRESSNODEPORTIP:$NODEPORT




#Demo 3 - Multiple Services with path based routing
#Let's create two additional services
kubectl create deployment hello-world-service-blue --image=psk8s.azurecr.io/hello-app:1.0
kubectl create deployment hello-world-service-red  --image=psk8s.azurecr.io/hello-app:1.0

kubectl expose deployment hello-world-service-blue --port=4343 --target-port=8080 --type=ClusterIP
kubectl expose deployment hello-world-service-red  --port=4242 --target-port=8080 --type=ClusterIP


#Let's create an ingress with paths each routing to different backend services.
kubectl apply -f ingress-path.yaml


#We now have two, one for all hosts and the other for our defined host with two paths
#The Ingress controller is implementing these ingresses and we're sharing the one public IP, don't proceed until you see 
#the address populated for your ingress
kubectl get ingress --watch


#We can see the host, the path, and the backends.
kubectl describe ingress ingress-path


#Our ingress on all hosts is still routing to service single, since we're accessing the URL with an IP and not a domain name or host header.
curl http://$INGRESSNODEPORTIP:$NODEPORT


#Our paths are routing to their correct services, if we specify a host header or use a DNS name to access the ingress. That's how the rule will route the request.
curl http://$INGRESSNODEPORTIP:$NODEPORT/red  --header 'Host: path.example.com'
curl http://$INGRESSNODEPORTIP:$NODEPORT/blue --header 'Host: path.example.com'


#Example Prefix matches...these will all match and get routed to red
curl http://$INGRESSNODEPORTIP:$NODEPORT/red/1  --header 'Host: path.example.com'
curl http://$INGRESSNODEPORTIP:$NODEPORT/red/2  --header 'Host: path.example.com'


#Example Exact mismatches...these will all 404
curl http://$INGRESSNODEPORTIP:$NODEPORT/Blue  --header 'Host: path.example.com'
curl http://$INGRESSNODEPORTIP:$NODEPORT/blue/1  --header 'Host: path.example.com'
curl http://$INGRESSNODEPORTIP:$NODEPORT/blue/2  --header 'Host: path.example.com'


#If we don't specify a path we'll get a 404 while specifying a host header. 
#We'll need to configure a path and backend for / or define a default backend for the service
curl http://$INGRESSNODEPORTIP:$NODEPORT/     --header 'Host: path.example.com'


#Add a backend to the ingress listenting on path.example.com pointing to the single service
kubectl apply -f ingress-path-backend.yaml


#We can see the default backend, and in the Rules, the host, the path, and the backends.
kubectl describe ingress ingress-path


#Now we'll hit the default backend service, single for the undefined path.
curl http://$INGRESSNODEPORTIP:$NODEPORT/ --header 'Host: path.example.com'




#Demo 4 - Name based virtual hosts
#Now, let's route traffic to the services using named based virtual hosts rather than paths
kubectl apply -f ingress-namebased.yaml
kubectl get ingress --watch #Wait for the Address to be populated before proceeding

curl http://$INGRESSNODEPORTIP:$NODEPORT/ --header 'Host: red.example.com'
curl http://$INGRESSNODEPORTIP:$NODEPORT/ --header 'Host: blue.example.com'




#Demo 5 - TLS Example
#1 - Generate a certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout tls.key -out tls.crt -subj "/C=US/ST=ILLINOIS/L=CHICAGO/O=IT/OU=IT/CN=tls.example.com"


#2 - Create a secret with the key and the certificate
kubectl create secret tls tls-secret --key tls.key --cert tls.crt


#3 - Create an ingress using the certificate and key. This uses HTTPS for both / and /red 
kubectl apply -f ingress-tls.yaml


#Check the status...do we have an IP?
kubectl get ingress --watch #Wait for the Address to be populated before proceeding


#Test access to the hostname...we need --resolve because we haven't registered the DNS name
#TLS is a layer lower than host headers, so we have to specify the correct DNS name. 
kubectl get service -n ingress-nginx ingress-nginx-controller
NODEPORTHTTPS=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{ .spec.ports[?(@.name=="https")].nodePort }')
echo $NODEPORTHTTPS
curl https://tls.example.com:$NODEPORTHTTPS/ \
    --resolve tls.example.com:$NODEPORTHTTPS:$INGRESSNODEPORTIP \
    --insecure --verbose


#Clean up from our demo
kubectl delete ingresses ingress-path
kubectl delete ingresses ingress-tls
kubectl delete ingresses ingress-namebased
kubectl delete deployment hello-world-service-single
kubectl delete deployment hello-world-service-red
kubectl delete deployment hello-world-service-blue
kubectl delete service hello-world-service-single
kubectl delete service hello-world-service-red
kubectl delete service hello-world-service-blue
kubectl delete secret tls-secret
rm tls.crt
rm tls.key

#Delete the ingress, ingress controller and other configuration elements
kubectl delete -f ./baremetal/deploy.yaml



##########################################################
#################### ingress-loadbalance #################
##########################################################

ssh aen@c1-cp1
cd ~/content/course/04/demos/

#Check out 1-ingress-nodeport.sh for the on-prem demos

#Demo 1 - Deploying an ingress controller
#For our Ingress Controller, we're going to go with nginx, widely available and easy to use. 
#Follow this link here to find a manifest for nginx Ingress Controller for various infrastructures, Cloud, Bare Metal, EKS and more.
#We have to choose a platform to deploy in...we can choose Cloud, Bare-metal (which we can use in our local cluster) and more.
https://kubernetes.github.io/ingress-nginx/deploy/


#Cloud: Azure (Same for GCE-GKE) This Ingress Controller will be exposed as a LoadBalancer service on a real public IP.
#Let's make sure we're in the right context and deploy the manifest for the Ingress Controller found in the link just above (around line 9).
kubectl config use-context 'CSCluster'
kubectl apply -f ./cloud/deploy.yaml


#Using this manifest, the Ingress Controller is in the ingress-nginx namespace but 
#It will monitor for Ingresses in all namespaces by default. If can be scoped to monitor a specific namespace if needed.


#Check the status of the pods to see if the ingress controller is online.
kubectl get pods --namespace ingress-nginx


#Now let's check to see if the service is online. This of type LoadBalancer, so do you have an EXTERNAL-IP?
kubectl get services --namespace ingress-nginx


#Check out the ingressclass nginx...we have not set the is-default-class so in each of our Ingresses we will need 
#specify an ingressclassname
kubectl describe ingressclasses nginx
#kubectl annotate ingressclasses nginx "ingressclass.kubernetes.io/is-default-class=true"


#Demo 2 - Single Service
#Create a deployment, scale it to 2 replicas and expose it as a serivce. 
#This service will be ClusterIP and we'll expose this service via the Ingress.
kubectl create deployment hello-world-service-single --image=psk8s.azurecr.io/hello-app:1.0
kubectl scale deployment hello-world-service-single --replicas=2
kubectl expose deployment hello-world-service-single --port=80 --target-port=8080 --type=ClusterIP



#Create a single Ingress routing to the one backend service on the service port 80 listening on all hostnames
kubectl apply -f ingress-single.yaml


#Get the status of the ingress. It's routing for all host names on that public IP on port 80
#This IP will be the same as the EXTERNAL-IP of the ingress controller...will take a second to update
#If you don't define an ingressclassname and don't have a default ingress class the address won't be updated.
kubectl get ingress --watch
kubectl get services --namespace ingress-nginx


#Notice the backends are the Service's Endpoints...so the traffic is going straight from the Ingress Controller to the Pod cutting out the kube-proxy hop.
#Also notice, the default backend is the same service, that's because we didn't define any rules and
#we just populated ingress.spec.backend. We're going to look at rules next...
kubectl describe ingress ingress-single


#Access the application via the exposed ingress on the public IP
INGRESSIP=$(kubectl get ingress -o jsonpath='{ .items[].status.loadBalancer.ingress[].ip }')
curl http://$INGRESSIP






#Demo 3 - Multiple Services with path based routing
#Let's create two additional services
kubectl create deployment hello-world-service-blue --image=psk8s.azurecr.io/hello-app:1.0
kubectl create deployment hello-world-service-red  --image=psk8s.azurecr.io/hello-app:1.0

kubectl expose deployment hello-world-service-blue --port=4343 --target-port=8080 --type=ClusterIP
kubectl expose deployment hello-world-service-red  --port=4242 --target-port=8080 --type=ClusterIP


#Let's create an ingress with paths each routing to different backend services.
kubectl apply -f ingress-path.yaml


#We now have two, one for all hosts and the other for our defined host with two paths
#The Ingress controller is implementing these ingresses and we're sharing the one public IP, don't proceed until you see 
#the address populated for your ingress
kubectl get ingress --watch


#We can see the host, the path, and the backends.
kubectl describe ingress ingress-path


#Our ingress on all hosts is still routing to service single, since we're accessing the URL with an IP and not a domain name or host header.
curl http://$INGRESSIP/


#Our paths are routing to their correct services, if we specify a host header or use a DNS name to access the ingress. That's how the rule will route the request.
curl http://$INGRESSIP/red  --header 'Host: path.example.com'
curl http://$INGRESSIP/blue --header 'Host: path.example.com'


#If we don't specify a path we'll get a 404 while specifying a host header. 
#We'll need to configure a path and backend for / or define a default backend for the service
curl http://$INGRESSIP/     --header 'Host: path.example.com'


#Let's add a backend to the ingress listenting on path.example.com pointing to the single service
kubectl apply -f ingress-path-backend.yaml


#We can see the default backend, and in the Rules, the host, the path, and the backends.
kubectl describe ingress ingress-path


#Now we'll hit the default backend service, single
curl http://$INGRESSIP/ --header 'Host: path.example.com'




#Demo 4 - Name based virtual hosts
#Now, let's route traffic to the services using named based virtual hosts rather than paths, wait for ADDRESS to be populated
kubectl apply -f ingress-namebased.yaml
kubectl get ingress --watch

curl http://$INGRESSIP/ --header 'Host: red.example.com'
curl http://$INGRESSIP/ --header 'Host: blue.example.com'




#TLS Example
#1 - Generate a certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout tls.key -out tls.crt -subj "/C=US/ST=ILLINOIS/L=CHICAGO/O=IT/OU=IT/CN=tls.example.com"


#2 - Create a secret with the key and the certificate
kubectl create secret tls tls-secret --key tls.key --cert tls.crt


#3 - Create an ingress using the certificate and key. This uses HTTPS for both / and /red 
kubectl apply -f ingress-tls.yaml


#Check the status...do we have an IP?
kubectl get ingress --watch


#Test access to the hostname...we need --resolve because we haven't registered the DNS name
#TLS is a layer lower than host headers, so we have to specify the correct DNS name. 
curl https://tls.example.com:443 --resolve tls.example.com:443:$INGRESSIP --insecure --verbose







#Clean up from our demo
kubectl delete ingresses ingress-path
kubectl delete ingresses ingress-tls
kubectl delete ingresses ingress-namebased
kubectl delete deployment hello-world-service-single
kubectl delete deployment hello-world-service-red
kubectl delete deployment hello-world-service-blue
kubectl delete service hello-world-service-single
kubectl delete service hello-world-service-red
kubectl delete service hello-world-service-blue
kubectl delete secret tls-secret
rm tls.crt
rm tls.key

#Delete the ingress, ingress controller and other configuration elements
kubectl delete -f ./cloud/deploy.yaml
