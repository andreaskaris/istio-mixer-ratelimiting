### How to deploy the application ###

All steps are in the Makefile.

> !!!! A word of caution- the following in create-project.sh will patch the istio-system ServiceMeshMemberRoll (smmr) default. This needs to be modified if the smmr name is different or if other projects shall be managed by istio, as well. In this case, only 2 projects, bookinfo and application will be managed by istio. Modify accordingly !!!!
~~~
cat create-project.sh
(...)
cat <<'EOF' | oc apply -n istio-system -f -
apiVersion: maistra.io/v1
kind: ServiceMeshMemberRoll
metadata:
  name: default
  namespace: istio-system
spec:
  members:
    # a list of projects joined into the service mesh
    - application
    - bookinfo
EOF
(...)
~~~

Follow the steps in the Makefile:
~~~
[stack@undercloud-0 istio]$ cat Makefile 
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
~~~

##### Prerequisites #####

Make sure to follow the following steps:
~~~
[stack@undercloud-0 istio]$ make prerequisites
bash configure-mixer.sh
From https://access.redhat.com/documentation/en-us/openshift_container_platform/4.3/html/service_mesh/day-two

     Log in to the OpenShift Container Platform CLI.

    Run this command to check the current Mixer policy enforcement status:

    $ oc get cm -n istio-system istio -o jsonpath='{.data.mesh}' | grep disablePolicyChecks

    If disablePolicyChecks: true, edit the Service Mesh ConfigMap:

    $ oc edit cm -n istio-system istio

    Locate disablePolicyChecks: true within the ConfigMap and change the value to false.
    Save the configuration and exit the editor.
    Re-check the Mixer policy enforcement status to ensure it is set to false.
~~~

##### Installing nginx #####

Now, install the nginx services:
~~~
make install-nginx
~~~

This will yield:
~~~
[stack@undercloud-0 istio]$ make install-nginx
bash create-project.sh
servicemeshcontrolplane.maistra.io/basic-install patched (no change)
servicemeshmemberroll.maistra.io/default unchanged
Already on project "application" on server "https://api.cluster43.example.com:6443".

You can add applications to this project with the 'new-app' command. For example, try:

    oc new-app ruby~https://github.com/sclorg/ruby-ex.git

to build a new example application in Python. Or use kubectl to deploy a simple Kubernetes application:

    kubectl create deployment hello-node --image=gcr.io/hello-minikube-zero-install/hello-node

securitycontextconstraints.security.openshift.io/anyuid added to: ["system:serviceaccount:application:default"]
oc apply -n application -f nginx-app-gateway.yaml
gateway.networking.istio.io/nginx-gateway created
virtualservice.networking.istio.io/nginx-gateway created
oc apply -n application -f nginx-a.yaml
configmap/nginx-deployment-a created
service/nginx-deployment-a created
deployment.apps/nginx-deployment-a created
oc apply -n application -f nginx-b.yaml
configmap/nginx-deployment-b created
service/nginx-deployment-b created
deployment.apps/nginx-deployment-b created
oc apply -n application -f nginx-c.yaml
configmap/nginx-deployment-c created
service/nginx-deployment-c created
deployment.apps/nginx-deployment-c created
~~~

~~~
[stack@undercloud-0 istio]$ oc get svc --show-labels
NAME                 TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)   AGE   LABELS
nginx-deployment-a   ClusterIP   172.30.24.49     <none>        80/TCP    47s   app=nginx-a,service=nginx-deployment-a
nginx-deployment-b   ClusterIP   172.30.226.212   <none>        80/TCP    46s   app=nginx-b,service=nginx-deployment-b
nginx-deployment-c   ClusterIP   172.30.155.12    <none>        80/TCP    45s   app=nginx-c,service=nginx-deployment-c
[stack@undercloud-0 istio]$ oc get pods --show-labels
NAME                                  READY   STATUS    RESTARTS   AGE   LABELS
nginx-deployment-a-d86b6f8ff-t8vzc    2/2     Running   0          51s   app=nginx-a,failure-domain.beta.kubernetes.io/region=regionOne,failure-domain.beta.kubernetes.io/zone=nova,pod-template-hash=d86b6f8ff,security.istio.io/tlsMode=istio
nginx-deployment-b-bcfbd7ff6-b4cmr    2/2     Running   0          50s   app=nginx-b,failure-domain.beta.kubernetes.io/region=regionOne,failure-domain.beta.kubernetes.io/zone=nova,pod-template-hash=bcfbd7ff6,security.istio.io/tlsMode=istio
nginx-deployment-c-59d7cf45fc-wd9h5   2/2     Running   0          50s   app=nginx-c,failure-domain.beta.kubernetes.io/region=regionOne,failure-domain.beta.kubernetes.io/zone=nova,pod-template-hash=59d7cf45fc,security.istio.io/tlsMode=istio
~~~

##### Installing the memquota limiter #####

Now that the services are installed, run:
~~~
make install-memquotarate-limit
~~~

~~~
[stack@undercloud-0 istio-mixer-ratelimiting]$ make install-memquotarate-limit
oc apply -f memquotaratelimit.yaml
handler.config.istio.io/quotahandler created
instance.config.istio.io/requestcountquota created
quotaspec.config.istio.io/request-count created
quotaspecbinding.config.istio.io/request-count created
rule.config.istio.io/quota created
~~~

Verification:
~~~
[stack@undercloud-0 istio-mixer-ratelimiting]$ oc get -f memquotaratelimit.yaml
NAME                                   AGE
handler.config.istio.io/quotahandler   4m18s

NAME                                         AGE
instance.config.istio.io/requestcountquota   4m18s

NAME                                      AGE
quotaspec.config.istio.io/request-count   4m18s

NAME                                             AGE
quotaspecbinding.config.istio.io/request-count   4m18s

NAME                         AGE
rule.config.istio.io/quota   4m18s
~~~

##### Verifying rate limiting #####

~~~
[stack@undercloud-0 istio-mixer-ratelimiting]$ for i in {0..10} ; do curl nginx.example.com/a ; done
Nginx A
Nginx A
Nginx A
Nginx A
Nginx A
Nginx A
RESOURCE_EXHAUSTED:Quota is exhausted for: requestcountquotaNginx A
RESOURCE_EXHAUSTED:Quota is exhausted for: requestcountquotaNginx A
Nginx A
~~~

~~~
[stack@undercloud-0 istio-mixer-ratelimiting]$ for i in {0..10} ; do curl nginx.example.com/b ; done
Nginx B
Nginx B
Nginx B
Nginx B
Nginx B
RESOURCE_EXHAUSTED:Quota is exhausted for: requestcountquotaRESOURCE_EXHAUSTED:Quota is exhausted for: requestcountquotaRESOURCE_EXHAUSTED:Quota is exhausted for: requestcountquotaRESOURCE_EXHAUSTED:Quota is exhausted for: requestcountquotaRESOURCE_EXHAUSTED:Quota is exhausted for: requestcountquotaRESOURCE_EXHAUSTED:Quota is exhausted for: requestcountquota
~~~

~~~
[stack@undercloud-0 istio-mixer-ratelimiting]$ for i in {0..10} ; do curl nginx.example.com/c ; done
Nginx C
RESOURCE_EXHAUSTED:Quota is exhausted for: requestcountquotaNginx C
RESOURCE_EXHAUSTED:Quota is exhausted for: requestcountquotaNginx C
RESOURCE_EXHAUSTED:Quota is exhausted for: requestcountquotaRESOURCE_EXHAUSTED:Quota is exhausted for: requestcountquotaRESOURCE_EXHAUSTED:Quota is exhausted for: requestcountquotaRESOURCE_EXHAUSTED:Quota is exhausted for: requestcountquotaRESOURCE_EXHAUSTED:Quota is exhausted for: requestcountquotaRESOURCE_EXHAUSTED:Quota is exhausted for: requestcountquota[stack@undercloud-0 istio-mixer-ratelimiting]$
~~~

If this does not work, see the troubleshooting steps below.

##### Using redisquote limiter ####

Uninstall the memquota limiter from the previous step:
~~~
[stack@undercloud-0 istio-mixer-ratelimiting]$ oc delete -f memquotaratelimit.yaml 
handler.config.istio.io "quotahandler" deleted
instance.config.istio.io "requestcountquota" deleted
quotaspec.config.istio.io "request-count" deleted
quotaspecbinding.config.istio.io "request-count" deleted
rule.config.istio.io "quota" deleted
~~~

Install a redis instance. For example:
~~~
make install-redis
~~~

In this case, the redis instance listens on 172.16.0.227:6379
~~~
[stack@undercloud-0 istio-mixer-ratelimiting]$ oc get svc -n redis
NAME           TYPE           CLUSTER-IP      EXTERNAL-IP    PORT(S)          AGE
redis-master   LoadBalancer   172.30.123.47   172.16.0.227   6379:30696/TCP   22h
~~~

Modify the following and set the correct URL:
~~~
spec:
  params:
    redisServerUrl: 172.16.0.227:6379
~~~

~~~
[stack@undercloud-0 istio-mixer-ratelimiting]$ make install-redisrate-limit
oc apply -f redisratelimit.yaml
handler.config.istio.io/redishandler created
instance.config.istio.io/requestcountquota created
quotaspec.config.istio.io/request-count created
quotaspecbinding.config.istio.io/request-count created
rule.config.istio.io/quota created
~~~

If this does not work, see the troubleshooting steps below

##### Verification #####

~~~
[stack@undercloud-0 istio-mixer-ratelimiting]$ sleep 30 ; for i in {0..10} ; do curl nginx.example.com/a ; done ; sleep 30 ; for i in {0..10} ; do curl nginx.example.com/b ; done ; sleep 30 ; for i in {0..10} ; do curl nginx.example.com/c ; done
Nginx A
RESOURCE_EXHAUSTED:Quota is exhausted for: requestcountquotaNginx A
Nginx A
Nginx A
Nginx A
Nginx A
Nginx A
Nginx A
Nginx A
Nginx A
Nginx B
RESOURCE_EXHAUSTED:Quota is exhausted for: requestcountquotaRESOURCE_EXHAUSTED:Quota is exhausted for: requestcountquotaRESOURCE_EXHAUSTED:Quota is exhausted for: requestcountquotaNginx B
Nginx B
RESOURCE_EXHAUSTED:Quota is exhausted for: requestcountquotaRESOURCE_EXHAUSTED:Quota is exhausted for: requestcountquotaNginx B
Nginx B
Nginx B
Nginx C
RESOURCE_EXHAUSTED:Quota is exhausted for: requestcountquotaNginx C
Nginx C
Nginx C
Nginx C
Nginx C
Nginx C
RESOURCE_EXHAUSTED:Quota is exhausted for: requestcountquotaRESOURCE_EXHAUSTED:Quota is exhausted for: requestcountquotaRESOURCE_EXHAUSTED:Quota is exhausted for: requestcountquota[stack@undercloud-0 istio-mixer-ratelimiting]$ 
~~~

### Caveats ###

##### Correct svc port #####

Note that it is *mandatory* that the service be defined with an http (or TLS) port spec:
~~~
  ports:
  - port: 80
    name: http
~~~

It cost me days of troubleshooting because initially, my nginx services were defined as TCP. The following does not work:
~~~
  - port: 80
    protocol: TCP
    targetPort: 80
~~~

##### redisquota crashes #####

Note that the redisquota adapter will crash when invalid values are used. For example, the redisquota adapter does not support `validDuration` in the overrides:
~~~
2020-05-28T15:50:48.762462Z	warn	unable to unmarshal: unknown field "validDuration" in config.Params_Override, {"connectionPoolSize":10,"quotas":[{"bucketDuration":"500ms","maxAmount":200,"name":"requestcountquota.instance.istio-system","overrides":[{"dimensions":{"destination":"nginx-deployment-a"},"maxAmount":10,"validDuration":"5s"},{"dimensions":{"destination":"nginx-deployment-b"},"maxAmount":10},{"dimensions":{"destination":"nginx-deployment-c"},"maxAmount":10}],"rateLimitAlgorithm":"ROLLING_WINDOW","validDuration":"5s"}],"redisServerUrl":"172.16.0.227:6379"}
(...)
[signal SIGSEGV: segmentation violation code=0x1 addr=0x8 pc=0x9f3ad7]

goroutine 2206 [running]:
istio.io/istio/mixer/adapter/redisquota/config.(*Params_Override).MarshalToSizedBuffer(0x0, 0xc0010e8b00, 0x67, 0x79, 0x79, 0xc0010e8b00, 0x12a05f200)
	istio.io/istio@/mixer/adapter/redisquota/config/config.pb.go:407 +0x37
istio.io/istio/mixer/adapter/redisquota/config.(*Params_Quota).MarshalToSizedBuffer(0xc00164ae10, 0xc0010e8b00, 0x67, 0x79, 0xe, 0x68, 0x80)
	istio.io/istio@/mixer/adapter/redisquota/config/config.pb.go:457 +0xbd
istio.io/istio/mixer/adapter/redisquota/config.(*Params).MarshalToSizedBuffer(0xc001798000, 0xc0010e8b00, 0x79, 0x79, 0x40a433, 0x2009560, 0x21e69e0)
	istio.io/istio@/mixer/adapter/redisquota/config/config.pb.go:373 +0x15a
istio.io/istio/mixer/adapter/redisquota/config.(*Params).Marshal(0xc001798000, 0x21e69e0, 0xc001798000, 0x7fb4b8713ee8, 0xc001798000, 0x1)
	istio.io/istio@/mixer/adapter/redisquota/config/config.pb.go:341 +0x7a
istio.io/istio/mixer/pkg/runtime/handler.encode(0x26c7920, 0xc000e2d9b0, 0x21e69e0, 0xc001798000, 0xc000bad601)
	istio.io/istio@/mixer/pkg/runtime/handler/signature.go:111 +0x1c4
istio.io/istio/mixer/pkg/runtime/handler.calculateSignature(0x2729c40, 0xc0015f5fb0, 0x1ebf3e0, 0xc0014a1040, 0x0, 0x0, 0x0)
	istio.io/istio@/mixer/pkg/runtime/handler/signature.go:67 +0x7c7
istio.io/istio/mixer/pkg/runtime/handler.createEntry(0xc000e1b620, 0xc000e2db90, 0x2729c40, 0xc0015f5fb0, 0x1ebf3e0, 0xc0014a1040, 0x59, 0xc000badbb8, 0x0, 0x1, ...)
	istio.io/istio@/mixer/pkg/runtime/handler/table.go:131 +0x6a
istio.io/istio/mixer/pkg/runtime/handler.NewTable(0xc000e1b620, 0xc000d29d80, 0xc0003fc360, 0x26de740, 0xc0003d37c0, 0x0, 0x0, 0x0, 0xc000ee1a00)
	istio.io/istio@/mixer/pkg/runtime/handler/table.go:83 +0x2c1
istio.io/istio/mixer/pkg/runtime.(*Runtime).processNewConfig(0xc00021c960)
	istio.io/istio@/mixer/pkg/runtime/runtime.go:167 +0x135
istio.io/istio/mixer/pkg/runtime.(*Runtime).onConfigChange(0xc00021c960, 0xc000352680, 0x14, 0x32)
	istio.io/istio@/mixer/pkg/runtime/runtime.go:155 +0x5b
istio.io/istio/mixer/pkg/config/store.WatchChanges(0xc00002af60, 0xc000a85080, 0x3b9aca00, 0xc000badfb0)
	istio.io/istio@/mixer/pkg/config/store/listener.go:62 +0x23d
istio.io/istio/mixer/pkg/runtime.(*Runtime).StartListening.func1(0xc00002af60, 0xc00021c960)
	istio.io/istio@/mixer/pkg/runtime/runtime.go:128 +0x6c
created by istio.io/istio/mixer/pkg/runtime.(*Runtime).StartListening
	istio.io/istio@/mixer/pkg/runtime/runtime.go:127 +0x187
~~~

~~~
[stack@undercloud-0 istio-mixer-ratelimiting]$ oc get pods -n istio-system
NAME                                      READY   STATUS             RESTARTS   AGE
details-v1-d7db4d55b-mpxvc                1/1     Running            0          168m
grafana-76f6446dbc-9wlkj                  2/2     Running            0          23h
ior-6d5f94cc7-xqw5m                       1/1     Running            0          23h
istio-citadel-6d5f6954b-kp5mw             1/1     Running            0          23h
istio-egressgateway-686897485c-p67f7      1/1     Running            0          23h
istio-galley-7d785cd74-c6xgk              1/1     Running            0          23h
istio-ingressgateway-69d89fbdfc-8n7gt     1/1     Running            0          23h
istio-pilot-774dbf49b8-kqw5b              2/2     Running            0          23h
istio-policy-548f54dc4f-4jppx             1/2     CrashLoopBackOff   15         23h
istio-sidecar-injector-55f45f76b5-xb5zs   1/1     Running            0          23h
istio-telemetry-85c546dc76-fqtgb          1/2     CrashLoopBackOff   15         23h
jaeger-5ff4756897-zh4qx                   2/2     Running            0          23h
kiali-78c65b695b-tjzpm                    1/1     Running            0          152m
productpage-v1-5f598fbbf4-n66h8           1/1     Running            0          168m
prometheus-66854d8c46-2k8v5               2/2     Running            0          23h
ratings-v1-85957d89d8-p7qqv               1/1     Running            0          168m
reviews-v1-67d9b4bcc-btcw6                1/1     Running            0          168m
~~~

### Troubleshooting mixer ###

Here are troubleshooting steps for mixer:

Use this to enable debugging for mixer:
https://github.com/istio/istio/wiki/Collecting-Logs-and-Debug-Information
https://istio.io/docs/ops/diagnostic-tools/controlz/

Get names of mixer pods:
~~~
[stack@undercloud-0 ~]$ oc get pods -n istio-system -l chart=mixer
NAME                               READY   STATUS    RESTARTS   AGE
istio-policy-548f54dc4f-4jppx      2/2     Running   13         19h
istio-telemetry-85c546dc76-fqtgb   2/2     Running   13         19h
~~~

Enable port forwarding to the policy pod:
~~~
kubectl --namespace istio-system port-forward istio-policy-548f54dc4f-4jppx 9876
~~~

Then, go to: http://127.0.0.1:9876/  to open the Control-Z interface
Open http://127.0.0.1:9876/scopez/ to switch all logging to debug via the web interface.

Next, use this to see mixer logs:
~~~
oc logs -n istio-system istio-policy-548f54dc4f-4jppx -c mixer -f
oc logs -n istio-system istio-telemetry-85c546dc76-fqtgb -c mixer -f
~~~

The logs for the policy pod are the interesting logs and should now show debug information.

When the quota adapters are called, one can then see this in the logs - *if* the quota adapters are called. E.g., this will only show if the service is defined as type http with port 80:
~~~
2020-05-28T15:00:10.780843Z	debug	api	Dispatching Check
2020-05-28T15:00:10.780855Z	debug	No destinations found for variety: table='65', variety='0'
2020-05-28T15:00:10.780860Z	debug	api	Check approved
2020-05-28T15:00:10.780868Z	debug	api	Dispatching Quota: requestcountquota
2020-05-28T15:00:10.780874Z	debug	no rules for namespace, using defaults: table='65', variety='2', ns='bookinfo'
2020-05-28T15:00:10.780894Z	debug	begin dispatch: destination='quota:quotahandler.istio-system(memquota)'
2020-05-28T15:00:10.780952Z	debug	adapters	quota default: 500 selected for {requestcountquota.instance.istio-system map[destination:nginx-a]}	{"adapter": "quotahandler.istio-system"}
2020-05-28T15:00:10.780971Z	debug	adapters	 AccessLog 10/10 requestcountquota.instance.istio-system;destination=nginx-a	{"adapter": "quotahandler.istio-system"}
2020-05-28T15:00:10.780978Z	debug	complete dispatch: destination='quota:quotahandler.istio-system(memquota)' {err:<nil>}
2020-05-28T15:00:10.781000Z	debug	api	Quota 'requestcountquota' result: v1.CheckResponse_QuotaResult{ValidDuration:1000000000, GrantedAmount:10, Status:google_rpc.Status{Code:0, Message:"", Details:[]*types.Any(nil)}, ReferencedAttributes:v1.ReferencedAttributes{Words:[]string(nil), AttributeMatches:[]v1.ReferencedAttributes_AttributeMatch(nil)}}
2020-05-28T15:00:11.765366Z	debug	adapters	Running repear to reclaim 1 old deduplication entries	{"adapter": "quotahandler.istio-system"}
2020-05-28T15:00:12.765352Z	debug	adapters	Running repear to reclaim 1 old deduplication entries	{"adapter": "quotahandler.istio-system"}
~~~

Then, one can create matching expressions based on the following debug output:
~~~
check.cache_hit               : true
connection.mtls               : false
context.protocol              : http
context.proxy_version         : 65535.65535.65535
context.reporter.kind         : inbound
context.reporter.uid          : kubernetes://nginx-deployment-a-d86b6f8ff-z67kj.application
destination.ip                : [0 0 0 0 0 0 0 0 0 0 255 255 172 26 2 8]
destination.namespace         : application
destination.port              : 80
destination.service.host      : nginx-deployment-a.application.svc.cluster.local
destination.service.name      : nginx-deployment-a
destination.service.namespace : application
destination.service.uid       : istio://application/services/nginx-deployment-a
destination.uid               : kubernetes://nginx-deployment-a-d86b6f8ff-z67kj.application
origin.ip                     : [172 26 2 17]
quota.cache_hit               : true
request.headers               : stringmap[:authority:nginx.example.com :method:GET :path:/ accept:*/* content-length:0 forwarded:for=172.16.0.93;host=nginx.example.com;proto=http;proto-version="" user-agent:curl/7.29.0 x-b3-sampled:1 x-b3-spanid:ba3c40ad06ccf65b x-b3-traceid:b8cd2e66d1f0727dba3c40ad06ccf65b x-envoy-external-address:172.27.2.1 x-envoy-original-path:/a x-forwarded-for:172.16.0.93,172.27.2.1 x-forwarded-host:nginx.example.com x-forwarded-port:80 x-forwarded-proto:http x-request-id:9d154125-5e2c-9fe4-86a7-90da8fed621b]
request.host                  : nginx.example.com
request.method                : GET
request.path                  : /
request.scheme                : http
request.time                  : 2020-05-28 15:07:22.530284006 +0000 UTC
request.url_path              : /
request.useragent             : curl/7.29.0
source.uid                    : kubernetes://istio-ingressgateway-69d89fbdfc-8n7gt.istio-system
---
destination.container.name    : nginx-a
destination.labels            : stringmap[app:nginx-a failure-domain.beta.kubernetes.io/region:regionOne failure-domain.beta.kubernetes.io/zone:nova pod-template-hash:d86b6f8ff security.istio.io/tlsMode:istio]
destination.name              : nginx-deployment-a-d86b6f8ff-z67kj
destination.owner             : kubernetes://apis/apps/v1/namespaces/application/deployments/nginx-deployment-a
destination.serviceAccount    : default
destination.workload.name     : nginx-deployment-a
destination.workload.namespace: application
destination.workload.uid      : istio://application/workloads/nginx-deployment-a
source.ip                     : [0 0 0 0 0 0 0 0 0 0 255 255 172 26 2 17]
source.labels                 : stringmap[app:istio-ingressgateway chart:gateways heritage:Tiller istio:ingressgateway maistra-control-plane:istio-system pod-template-hash:69d89fbdfc release:istio]
source.name                   : istio-ingressgateway-69d89fbdfc-8n7gt
source.namespace              : istio-system
source.owner                  : kubernetes://apis/apps/v1/namespaces/istio-system/deployments/istio-ingressgateway
source.serviceAccount         : istio-ingressgateway-service-account
source.workload.name          : istio-ingressgateway
source.workload.namespace     : istio-system
source.workload.uid           : istio://istio-system/workloads/istio-ingressgateway
~~~

For example, I chose `destination.service.name = nginx-deployment-a` and thus created the following expression, meaning that field `destination` will be populated with the content of `destination.service.name`:
~~~
apiVersion: config.istio.io/v1alpha2
kind: instance
metadata:
  name: requestcountquota
  namespace: istio-system
spec:
  compiledTemplate: quota
  params:
    dimensions:
      destination: destination.service.name | "unknown"
~~~

Then, I'm matching on the destination filed (destination.service.name):
~~~
apiVersion: config.istio.io/v1alpha2
kind: handler
metadata:
  name: quotahandler
  namespace: istio-system
spec:
  compiledAdapter: memquota
  params:
    quotas:
    - name: requestcountquota.instance.istio-system
      maxAmount: 500
      validDuration: 1s
      # The first matching override is applied.
      # A requestcount instance is checked against override dimensions.
      overrides:
      # The following override applies to 'reviews' regardless
      # of the source.
      - dimensions:
          destination: nginx-deployment-a
        maxAmount: 10
        validDuration: 5s
      - dimensions:
          destination: nginx-deployment-b
        maxAmount: 5
        validDuration: 5s
      - dimensions:
          destination: nginx-deployment-c
        maxAmount: 1
        validDuration: 5s
~~~

### Applying rate limiting only to a specific namespace

It is possible to apply the ratelimit only to a specific namespace, not globally:
~~~
sed -i 's/istio-system/application/g' memquotaratelimit.yaml
~~~
