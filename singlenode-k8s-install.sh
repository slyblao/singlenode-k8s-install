#!/bin/sh

echo -----------------------------------------------------------------------------------------------------------------------------------------------------------------
echo --------------------------------- BE SURE YOUR VIRTUAL MACHINE HAS AT LEAST 2 CPUs ------------------------------------------------------------------------------
echo --------------------------------- IF YOU DO NOT HAVE 2 CPUs YOUR INSTALL WILL FAIL ------------------------------------------------------------------------------
echo --------------------------------- STOP THIS INSTALLATION SCRIPT AND RESUME AFTER YOUHAVE ADDED THE REQUIRED CPU COUNT--------------------------------------------
echo -----------------------------------------------------------------------------------------------------------------------------------------------------------------
sleep 30
echo ------------------------------------------------------------------------------------------------------------------------------------------------------------------
echo --------------------------------- STARTING SINGLE NODE INSTALL ---------------------------------------------------------------------------------------------------
apt-get update && apt-get install -y curl apt-transport-https
swapoff -a

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
cat <<EOF >/etc/apt/sources.list.d/docker.list
deb https://download.docker.com/linux/$(lsb_release -si | tr '[:upper:]' '[:lower:]') $(lsb_release -cs) stable
EOF
apt-get update && apt-get install -y docker-ce=$(apt-cache madison docker-ce | grep 17.03 | head -1 | awk '{print $3}')

curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF
apt-get update
apt-get install -y docker.io
apt-get install -y kubeadm=1.16\* kubectl=1.16\* kubelet=1.16\* kubernetes-cni
apt  install jq -y

sudo systemctl enable docker.service

echo #######
echo #######

echo ------------------------------------------ READY TO INITIALIZE CLUSTER WITH kubeadm init ---------------------------------------

sleep 15

kubeadm init --pod-network-cidr=192.168.0.0/16

sleep 15

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
echo #######
echo #######
# Allow workloads to be scheduled to the master node
echo ------------------------------------------ ALLOW PODS TO BE SCHEDULED ON MASTER --------------------------------------------
kubectl taint nodes --all node-role.kubernetes.io/master-

sleep 15


kubectl get pods --all-namespaces

sleep 30


kubectl apply -f https://docs.projectcalico.org/v3.10/manifests/calico.yaml

sleep 60

kubectl get pods --all-namespaces

sleep 60

echo ------------------------------------------ CHECKING FOR ALL RUNNING PODS --------------------------------------------
kubectl get pods --all-namespaces

sleep 60
echo ------------------------------------------ INSTALL METRIC-SERVER ------------------------------------------------------
# The commands below will install metric-server

sudo bash -c 'cat << EOF > metric-deployment.yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: metrics-server
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: metrics-server:system:auth-delegator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
  - kind: ServiceAccount
    name: metrics-server
    namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: metrics-server-auth-reader
  namespace: kube-system
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: extension-apiserver-authentication-reader
subjects:
  - kind: ServiceAccount
    name: metrics-server
    namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: system:metrics-server
rules:
  - apiGroups:
      - ""
    resources:
      - pods
      - nodes
      - nodes/stats
      - namespaces
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - "extensions"
    resources:
      - deployments
    verbs:
      - get
      - list
      - watch
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: system:aggregated-metrics-reader
  labels:
    rbac.authorization.k8s.io/aggregate-to-view: "true"
    rbac.authorization.k8s.io/aggregate-to-edit: "true"
    rbac.authorization.k8s.io/aggregate-to-admin: "true"
rules:
  - apiGroups: ["metrics.k8s.io"]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:metrics-server
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:metrics-server
subjects:
  - kind: ServiceAccount
    name: metrics-server
    namespace: kube-system
---
apiVersion: apiregistration.k8s.io/v1beta1
kind: APIService
metadata:
  name: v1beta1.metrics.k8s.io
spec:
  service:
    name: metrics-server
    namespace: kube-system
  group: metrics.k8s.io
  version: v1beta1
  insecureSkipTLSVerify: true
  groupPriorityMinimum: 100
  versionPriority: 100
---
apiVersion: v1
kind: Service
metadata:
  name: metrics-server
  namespace: kube-system
  labels:
    kubernetes.io/name: "Metrics-server"
spec:
  selector:
    k8s-app: metrics-server
  ports:
    - port: 443
      protocol: TCP
      targetPort: 443
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: metrics-server
  namespace: kube-system
  labels:
    k8s-app: metrics-server
spec:
  selector:
    matchLabels:
      k8s-app: metrics-server
  template:
    metadata:
      name: metrics-server
      labels:
        k8s-app: metrics-server
    spec:
      serviceAccountName: metrics-server
      volumes:
      # mount in tmp so we can safely use from-scratch images and/or read-only containers
      - name: tmp-dir
        emptyDir: {}
      containers:
      - name: metrics-server
        image: k8s.gcr.io/metrics-server-amd64:v0.3.6
        imagePullPolicy: Always
        command:
            - /metrics-server
            - --kubelet-preferred-address-types=InternalIP,Hostname,ExternalIP
            - --kubelet-insecure-tls
        volumeMounts:
        - name: tmp-dir
          mountPath: /tmp
EOF'

sleep 15
kubectl apply -f metric-deployment.yaml


sleep 60
echo ------------------------------------------ METRIC-SERVER INSTALLED --------------------------------------------------
echo #######
echo #######
echo ------------------------------------------ INSTALL DASHBOARD --------------------------------------------------------
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0-beta4/aio/deploy/recommended.yaml
echo #######
echo #######
echo ------------------------------------------ DASHBOARD INSTALLED --------------------------------------------------------
sleep 60
# Create an admin user that will be needed in order to access the Kubernetes Dashboard
sudo bash -c 'cat << EOF > admin-user.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
EOF'

kubectl create -f admin-user.yaml

# Create an admin role that will be needed in order to access the Kubernetes Dashboard
sudo bash -c 'cat << EOF > role-binding.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
EOF'

kubectl create -f role-binding.yaml
echo #######
echo #######
sleep 10
kubectl get pods --all-namespaces
sleep 10
echo #######
echo #######
echo -------------------------------- TOKEN FOR JONING ANOTHER NODE TO CLUSTER -------------------------------------------
# This command will create a token and print the command needed to join slave workers
kubeadm token create --print-join-command --ttl 24h
echo ----------------------------------------- TOKEN FOR DASHBOARD --------------------------------------------------------
sleep 10
# Now we need to find token we can use to log in. Execute following command:
kubectl -n kubernetes-dashboard describe secret $(kubectl -n kubernetes-dashboard get secret | grep admin-user | awk '{print $1}')
sleep 10
echo ---------------------------------------------------------------------------------------------------------------------
echo ALL
echo DONE
echo HERE
echo ---------------------------------------------------------------------------------------------------------------------
echo PLAY NICE, YOU KNOW HAVE A RUNNING KUBERNETES INSTANCE WITH METRICS AND DASHBOARD!!!!!!
echo ---------------------------------------------------------------------------------------------------------------------
echo Access Kubernetes Dashboard using Kubectl proxy..... To do this you will spin up a proxy server between our local machine and the Kubernetes apiserver.
echo Access dashboard with ths URL http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/#/login
echo ---------------------------------------------------------------------------------------------------------------------
echo ------------------------------------------------- Sly.B -------------------------------------------------------------
echo ---------------------------------------------------------------------------------------------------------------------
echo #######
echo #######
echo #######
echo #######
echo #######
echo #######