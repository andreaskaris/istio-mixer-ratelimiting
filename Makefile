prerequisites:
	bash configure-mixer.sh

install-nginx:
	bash create-project.sh
	oc apply -n application -f nginx-app-gateway.yaml
	oc apply -n application -f nginx-a.yaml
	oc apply -n application -f nginx-b.yaml
	oc apply -n application -f nginx-c.yaml

install-memquotarate-limit:
	oc apply -f memquotaratelimit.yaml

install-redis:
	oc new-project redis
	oc apply -n redis -f redis-master-deployment.yaml

install-redisrate-limit:
	oc apply -f redisratelimit.yaml
