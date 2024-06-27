gcloud config set compute/region $REGION
gcloud config set compute/zone $ZONE

# create startup script
cat << EOF > startup.sh
#! /bin/bash
apt-get update
apt-get install -y nginx
service nginx start
sed -i -- 's/nginx/Google Cloud Platform - '"\$HOSTNAME"'/' /var/www/html/index.nginx-debian.html
EOF

# create load balancer template
gcloud compute instance-templates create web-server-template \
  --metadata-from-file startup-script=startup.sh \
  --machine-type e2-medium \
  --region $ZONE

# create managed instance groups based on template
gcloud compute instance-groups managed create web-server-group \
  --base-instance-name web-server \
  --size 2 \
  --template web-server-template \
  --region $REGION

gcloud compute instance-groups managed \
set-named-ports web-server-group \
--named-ports http:80 \
--region $REGION

# create firewall rule
gcloud compute firewall-rules create $FIREWALL_NAME --allow tcp:80

# create health check
gcloud compute health-checks create http http-basic-check --port 80

# create backend service
gcloud compute backend-services create web-backend-service \
  --protocol=HTTP \
  --port-name=http \
  --health-checks=http-basic-check \
  --global

# add instance group as the backend to the backend service
gcloud compute backend-services add-backend web-backend-service \
  --instance-group=web-server-group \
  --instance-group-region $REGION \
  --global

# create a URL map to route the incoming requests to the default backend service
gcloud compute url-maps create web-map-http --default-service web-backend-service

# create a target HTTP proxy to route requests to the URL map
gcloud compute target-http-proxies create http-lb-proxy --url-map web-map-http

# create a global forwarding rule to route incoming requests to the proxy
gcloud compute forwarding-rules create http-content-rule \
   --global \
   --target-http-proxy=http-lb-proxy \
   --ports=$PORT
