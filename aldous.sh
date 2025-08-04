#!/usr/bin/env bash

docker build -t localhost:32000/aldous:latest -f Dockerfile.aldous .
docker push localhost:32000/aldous:latest

cat <<'EOF' | microk8s kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: aldous
spec:
  replicas: 2
  selector:
    matchLabels:
      app: aldous
  template:
    metadata:
      labels:
        app: aldous
    spec:
      containers:
      - name: php
        image: localhost:32000/aldous:latest
        ports:
        - containerPort: 8000
---
apiVersion: v1
kind: Service
metadata:
  name: aldous
spec:
  selector:
    app: aldous
  ports:
  - port: 80
    targetPort: 8000
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: aldous-ingress
  annotations:
    kubernetes.io/ingress.class: kong
    konghq.com/plugins: oidc-protection
spec:
  tls:
  - hosts:
    - aldous.info
    secretName: aldous-tls
  rules:
  - host: aldous.info
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: aldous
            port:
              number: 80
EOF
