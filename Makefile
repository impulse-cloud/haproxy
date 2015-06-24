WEB_CONTAINERS = web-a web-b web-c web-d web-e web-f web-g web-h web-i web-j web-k web-l web-m web-n
LB_CONTAINERS = lb0 lb1 lb2 lb3 lb4 lb5 lb6
NODE_FQDN = http://302a494c-tifayuki.node.tutum.io
services = $(shell tutum service ps -q)
random := $(shell awk 'BEGIN{srand();printf("%d", 65536*rand())}')

test:test-unittest test-without-tutum test-with-tutum;

test-docker-available:
	@set -e
	@echo "==> Testing docker environment"
	docker version || (echo "==> Failed: cannot run docker" && false)
	@echo

clean:test-docker-available
	@set -e
	@echo "==> Cleaning tmp files and containers"
	docker rm -f $(WEB_CONTAINERS) $(LB_CONTAINERS) > /dev/null 2>&1 || true
	rm -f key.pem ca.pem cert.pem output
	@echo

create-cert:clean
	@set -e
	@echo "==> Generating certificate for tests"
	openssl req -x509 -newkey rsa:2048 -keyout key.pem -out ca.pem -days 1080 -nodes -subj '/CN=localhost/O=My Company Name LTD./C=US'
	cp key.pem cert.pem
	cat ca.pem >> cert.pem
	@echo

build:create-cert
	@set -e
	@echo "==> Building haproxy image"
	docker build -t tifayuki/haproxy-test .
	@echo

certs = $(shell awk 1 ORS='\\n' cert.pem)
test-without-tutum:build
	@set -e
	@echo "====== Running integration tests without Tutum ======"

	@echo "==> Testing if haproxy is running properly"
	docker run -d --name web-a -e HOSTNAME="web-a" tutum/hello-world
	docker run -d --name web-b -e HOSTNAME="web-b" tutum/hello-world
	docker run -d --name lb0 --link web-a:web-a --link web-b:web-b -p 8000:80 tifayuki/haproxy-test
	wget --spider --retry-connrefused --no-check-certificate -T 5 http://localhost:8000 > /dev/null
	curl --retry 10 --retry-delay 5 -L -I http://localhost:8000 | grep "200 OK" > /dev/null
	@echo

	@echo "==> Testing SSL settings"
	docker run -d --name lb1 --link web-a:web-a -e SSL_CERT="$(certs)" -p 443:443 tifayuki/haproxy-test
	sleep 5
	curl --retry 10 --retry-delay 5 -sSfL --cacert ca.pem -L https://localhost | grep 'My hostname is web-a' > /dev/null
	@echo

	@echo "==> Testing virtual host"
	docker run -d --name web-c -e HOSTNAME=web-c -e VIRTUAL_HOST=web-c.org tutum/hello-world
	docker run -d --name web-d -e HOSTNAME=web-d -e VIRTUAL_HOST="web-d.org, test.org" tutum/hello-world
	docker run -d --name lb2 --link web-c:web-c --link web-d:web-d -p 8002:80 tifayuki/haproxy-test
	wget --spider --retry-connrefused --no-check-certificate -q -T 5 127.0.0.1:8002 || true > /dev/null
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:web-c.org' 127.0.0.1:8002 | grep -iF 'My hostname is web-c' > /dev/null
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:test.org' 127.0.0.1:8002 | grep -iF 'My hostname is web-d' > /dev/null
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:web-d.org' 127.0.0.1:8002 | grep -iF 'My hostname is web-d' > /dev/null
	@echo

	@echo "==> Testing virtual host starting with wildcard"
	docker run -d --name web-e -e HOSTNAME=web-e -e VIRTUAL_HOST="*.web-e.org" tutum/hello-world
	docker run -d --name lb3 --link web-e:web-e -p 8003:80 tifayuki/haproxy-test
	wget --spider --retry-connrefused --no-check-certificate -q -T 5 127.0.0.1:8003 || true > /dev/null
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:www.web-e.org' 127.0.0.1:8003 | grep -iF 'My hostname is web-e' > /dev/null
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:abc.web-e.org' 127.0.0.1:8003 | grep -iF 'My hostname is web-e' > /dev/null
	curl -sSL -H 'Host:abc.web.org' 127.0.0.1:8003 | grep -iF '503 Service Unavailable' > /dev/null
	@echo

	@echo "==> Testing virtual host containing with wildcard"
	docker run -d --name web-f -e HOSTNAME=web-f -e VIRTUAL_HOST="www.web*.org" tutum/hello-world
	docker run -d --name lb4 --link web-f:web-f -p 8004:80 tifayuki/haproxy-test
	wget --spider --retry-connrefused --no-check-certificate -q -T 5 127.0.0.1:8004 || true > /dev/null
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:www.web.org' 127.0.0.1:8004 | grep -iF 'My hostname is web-f' > /dev/null
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:www.webtest.org' 127.0.0.1:8004 | grep -iF 'My hostname is web-f' > /dev/null
	curl -sSL -H 'Host:abc.wbbtest.org' 127.0.0.1:8004 | grep -iF '503 Service Unavailable' > /dev/null
	@echo

	@echo "==> Testing virtual path"
	docker run -d --name web-g -e HOSTNAME=web-g -e VIRTUAL_HOST="*/pg/, */pg, */pg/*, */*/pg/*" tutum/hello-world
	docker run -d --name web-h -e HOSTNAME=web-h -e VIRTUAL_HOST="*/ph" tutum/hello-world
	docker run -d --name web-i -e HOSTNAME=web-i -e VIRTUAL_HOST="*/pi/" tutum/hello-world
	docker run -d --name web-j -e HOSTNAME=web-j -e VIRTUAL_HOST="*/pj/*" tutum/hello-world
	docker run -d --name web-k -e HOSTNAME=web-k -e VIRTUAL_HOST="*/*/pk/*" tutum/hello-world
	docker run -d --name web-l -e HOSTNAME=web-l -e VIRTUAL_HOST="*/p*l/" tutum/hello-world
	docker run -d --name web-m -e HOSTNAME=web-m -e VIRTUAL_HOST="*/*.js" tutum/hello-world
	docker run -d --name lb5 --link web-g:web-g --link web-h:web-h --link web-i:web-i --link web-j:web-j --link web-k:web-k --link web-l:web-l --link web-m:web-m -p 8005:80 tifayuki/haproxy-test
	wget --spider --retry-connrefused --no-check-certificate -q -T 5 127.0.0.1:8005 || true > /dev/null
	curl --retry 10 --retry-delay 5 -sSfL 127.0.0.1:8005/pg | grep -iF 'My hostname is web-g' > /dev/null
	curl --retry 10 --retry-delay 5 -sSfL 127.0.0.1:8005/pg/ | grep -iF 'My hostname is web-g' > /dev/null
	curl --retry 10 --retry-delay 5 -sSfL 127.0.0.1:8005/pg/abc | grep -iF 'My hostname is web-g' > /dev/null
	curl --retry 10 --retry-delay 5 -sSfL 127.0.0.1:8005/abc/pg/ | grep -iF 'My hostname is web-g' > /dev/null
	curl --retry 10 --retry-delay 5 -sSfL 127.0.0.1:8005/abc/pg/123 | grep -iF 'My hostname is web-g' > /dev/null
	curl --retry 10 --retry-delay 5 -sSfL "127.0.0.1:8005/pg?u=user&p=pass" | grep -iF 'My hostname is web-g' > /dev/null

	curl --retry 10 --retry-delay 5 -sSfL 127.0.0.1:8005/ph | grep -iF 'My hostname is web-h' > /dev/null
	curl -sSL 127.0.0.1:8005/ph/ | grep -iF '503 Service Unavailable' > /dev/null
	curl -sSL 127.0.0.1:8005/ph/abc | grep -iF '503 Service Unavailable' > /dev/null
	curl -sSL 127.0.0.1:8005/abc/ph/ | grep -iF '503 Service Unavailable' > /dev/null
	curl -sSL 127.0.0.1:8005/abc/ph/123 | grep -iF '503 Service Unavailable' > /dev/null
	curl --retry 10 --retry-delay 5 -sSfL "127.0.0.1:8005/ph?u=user&p=pass" | grep -iF 'My hostname is web-h' > /dev/null

	curl -sSL 127.0.0.1:8005/pi | grep -iF '503 Service Unavailable' > /dev/null
	curl --retry 10 --retry-delay 5 -sSfL 127.0.0.1:8005/pi/ | grep -iF 'My hostname is web-i' > /dev/null
	curl -sSL 127.0.0.1:8005/pi/abc | grep -iF '503 Service Unavailable' > /dev/null
	curl -sSL 127.0.0.1:8005/abc/pi/ | grep -iF '503 Service Unavailable' > /dev/null
	curl -sSL 127.0.0.1:8005/abc/pi/123 | grep -iF '503 Service Unavailable' > /dev/null
	curl --retry 10 --retry-delay 5 -sSfL "127.0.0.1:8005/pi/?u=user&p=pass" | grep -iF 'My hostname is web-i' > /dev/null

	curl -sSL 127.0.0.1:8005/pj | grep -iF '503 Service Unavailable' > /dev/null
	curl --retry 10 --retry-delay 5 -sSfL 127.0.0.1:8005/pj/ | grep -iF 'My hostname is web-j' > /dev/null
	curl --retry 10 --retry-delay 5 -sSfL 127.0.0.1:8005/pj/abc | grep -iF 'My hostname is web-j' > /dev/null
	curl -sSL 127.0.0.1:8005/abc/pj/ | grep -iF '503 Service Unavailable' > /dev/null
	curl -sSL 127.0.0.1:8005/abc/pj/123 | grep -iF '503 Service Unavailable' > /dev/null
	curl --retry 10 --retry-delay 5 -sSfL "127.0.0.1:8005/pj/?u=user&p=pass" | grep -iF 'My hostname is web-j' > /dev/null
	curl --retry 10 --retry-delay 5 -sSfL "127.0.0.1:8005/pj/abc?u=user&p=pass" | grep -iF 'My hostname is web-j' > /dev/null

	curl -sSL 127.0.0.1:8005/pk | grep -iF '503 Service Unavailable' > /dev/null
	curl -sSL 127.0.0.1:8005/pk/ | grep -iF '503 Service Unavailable' > /dev/null
	curl -sSL 127.0.0.1:8005/pk/abc | grep -iF '503 Service Unavailable' > /dev/null
	curl --retry 10 --retry-delay 5 -sSfL 127.0.0.1:8005/abc/pk/ | grep -iF 'My hostname is web-k' > /dev/null
	curl --retry 10 --retry-delay 5 -sSfL 127.0.0.1:8005/abc/pk/123 | grep -iF 'My hostname is web-k' > /dev/null
	curl --retry 10 --retry-delay 5 -sSfL "127.0.0.1:8005/abc/pk/?u=user&p=pass" | grep -iF 'My hostname is web-k' > /dev/null
	curl --retry 10 --retry-delay 5 -sSfL "127.0.0.1:8005/abc/pk/123?u=user&p=pass" | grep -iF 'My hostname is web-k' > /dev/null

	curl -sSL 127.0.0.1:8005/pl | grep -iF '503 Service Unavailable' > /dev/null
	curl --retry 10 --retry-delay 5 -sSfL 127.0.0.1:8005/pl/ | grep -iF 'My hostname is web-l' > /dev/null
	curl -sSL 127.0.0.1:8005/p3l | grep -iF '503 Service Unavailable' > /dev/null
	curl --retry 10 --retry-delay 5 -sSfL 127.0.0.1:8005/p3l/ | grep -iF 'My hostname is web-l' > /dev/null
	curl --retry 10 --retry-delay 5 -sSfL "127.0.0.1:8005/pl/?u=user&p=pass" | grep -iF 'My hostname is web-l' > /dev/null
	curl --retry 10 --retry-delay 5 -sSfL "127.0.0.1:8005/p3l/?u=user&p=pass" | grep -iF 'My hostname is web-l' > /dev/null

	curl --retry 10 --retry-delay 5 -sSfL 127.0.0.1:8005/abc.js | grep -iF 'My hostname is web-m' > /dev/null
	curl --retry 10 --retry-delay 5 -sSfL 127.0.0.1:8005/path/123.js | grep -iF 'My hostname is web-m' > /dev/null
	curl --retry 10 --retry-delay 5 -sSfL "127.0.0.1:8005/abc.js?u=user&p=pass" | grep -iF 'My hostname is web-m' > /dev/null
	curl --retry 10 --retry-delay 5 -sSfL "127.0.0.1:8005/path/123.js?u=user&p=pass" | grep -iF 'My hostname is web-m' > /dev/null
	curl -sSL 127.0.0.1:8005/abc.jpg | grep -iF '503 Service Unavailable' > /dev/null
	curl -sSL 127.0.0.1:8005/path/abc.jpg | grep -iF '503 Service Unavailable' > /dev/null
	@echo

	@echo "==> Test virtual host combined with virtual path"
	docker run -d --name web-n -e HOSTNAME=web-n -e VIRTUAL_HOST="http://www.web-n.org/p3/" tutum/hello-world
	docker run -d --name lb6 --link web-n:web-n -p 8006:80 tifayuki/haproxy-test
	wget --spider --retry-connrefused --no-check-certificate -q -T 5 127.0.0.1:8006 || true > /dev/null
	curl --retry 10 --retry-delay 5 -H "Host:www.web-n.org" -sSfL 127.0.0.1:8006/p3/ | grep -iF 'My hostname is web-n' > /dev/null
	curl -sSL 127.0.0.1:8006/p3/ | grep -iF '503 Service Unavailable' > /dev/null
	curl -sSL -H "Host:www.web-n.org" 127.0.0.1:8006 | grep -iF '503 Service Unavailable' > /dev/null
	curl -sSL -H "Host:www.web-n.org" 127.0.0.1:8006/p3 | grep -iF '503 Service Unavailable' > /dev/null
	curl -sSL -H "Host:www.web.org" 127.0.0.1:8006/p3 | grep -iF '503 Service Unavailable' > /dev/null

push-image: build
	@echo "=> Pushing the image to tifayuki/haproxy"
	@echo "=> Logging in to docker"
	@docker login -u $(DOCKER_USER) -p $(DOCKER_PASS) -e a@a.com
	docker push tifayuki/haproxy-test
	@echo

clean-tutum-service:
	@echo "==> Terminating containers in Tuttum"
	tutum service terminate $(services) || true
	@echo

test-with-tutum:push-image clean-tutum-service
	@set -e
	@echo "====== Running integration tests with Tutum ======"

	@echo "==> Testing if haproxy is running propkrly with tutum"
	tutum service run --sync --name $(random)web-a -e HOSTNAME="web-a" tutum/hello-world
	tutum service run --sync --name $(random)web-b -e HOSTNAME="web-b" tutum/hello-world
	tutum service run --role global --sync --name $(random)lb1 --link $(random)web-a:web-a --link $(random)web-b:web-b -p 8000:80 tifayuki/haproxy-test
	wget --spider --retry-connrefused --no-check-certificate -q -T 5 $(NODE_FQDN):8000 || true
	curl --retry 10 --retry-delay 5 -sSfL -I $(NODE_FQDN):8000 | grep "200 OK"
	@echo

	@echo "==> Testing container stop"
	tutum service run -t 2 --sync --name $(random)web-f -e VIRTUAL_HOST=web-f.org tutum/hello-world
	tutum service run -t 2 --sync --name $(random)web-g -e VIRTUAL_HOST=web-g.org tutum/hello-world
	tutum service run --role global --name $(random)lb5 --link $(random)web-f:$(random)web-f --link $(random)web-g:$(random)web-g -p 8004:80 tifayuki/haproxy-test
	wget --spider --retry-connrefused --no-check-certificate -q -T 5 $(NODE_FQDN):8004 || true
	tutum container stop --sync $(random)web-f-1
	tutum container stop --sync $(random)web-g-1
	rm -f output
	sleep 5
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:web-f.org' $(NODE_FQDN):8004 >> output
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:web-f.org' $(NODE_FQDN):8004 >> output
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:web-g.org' $(NODE_FQDN):8004 >> output
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:web-g.org' $(NODE_FQDN):8004 >> output
	grep 'My hostname is $(random)web-f-2' output | wc -l | grep 2
	grep 'My hostname is $(random)web-g-2' output | wc -l | grep 2
	@echo

	@echo "==> Testing container start"
	tutum container start --sync $(random)web-f-1
	tutum container start --sync $(random)web-g-1
	rm -f output
	sleep 5
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:web-f.org' $(NODE_FQDN):8004 >> output
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:web-f.org' $(NODE_FQDN):8004 >> output
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:web-g.org' $(NODE_FQDN):8004 >> output
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:web-g.org' $(NODE_FQDN):8004 >> output
	grep 'My hostname is $(random)web-f-1' output | wc -l | grep 1
	grep 'My hostname is $(random)web-f-2' output | wc -l | grep 1
	grep 'My hostname is $(random)web-g-1' output | wc -l | grep 1
	grep 'My hostname is $(random)web-g-2' output | wc -l | grep 1
	@echo

	@echo "==> Testing container terminate"
	tutum container terminate --sync $(random)web-f-2
	tutum container terminate --sync $(random)web-g-2
	rm -f output
	sleep 5
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:web-f.org' $(NODE_FQDN):8004 >> output
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:web-f.org' $(NODE_FQDN):8004 >> output
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:web-g.org' $(NODE_FQDN):8004 >> output
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:web-g.org' $(NODE_FQDN):8004 >> output
	grep 'My hostname is $(random)web-f-1' output | wc -l | grep 2
	grep 'My hostname is $(random)web-g-1' output | wc -l | grep 2
	@echo

	@echo "==> Testing container redeploy"
	tutum container redeploy --sync $(random)web-f-1
	tutum container redeploy --sync $(random)web-g-1
	rm -f output
	sleep 5
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:web-f.org' $(NODE_FQDN):8004 >> output
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:web-f.org' $(NODE_FQDN):8004 >> output
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:web-g.org' $(NODE_FQDN):8004 >> output
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:web-g.org' $(NODE_FQDN):8004 >> output
	grep 'My hostname is $(random)web-f-1' output | wc -l | grep 2
	grep 'My hostname is $(random)web-g-1' output | wc -l | grep 2
	@echo

	@echo "==> Testing with service scale up"
	tutum service scale --sync $(random)web-f 2
	tutum service scale --sync $(random)web-g 2
	rm -f output
	sleep 5
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:web-f.org' $(NODE_FQDN):8004 >> output
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:web-f.org' $(NODE_FQDN):8004 >> output
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:web-g.org' $(NODE_FQDN):8004 >> output
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:web-g.org' $(NODE_FQDN):8004 >> output
	grep 'My hostname is $(random)web-f-1' output | wc -l | grep 1
	grep 'My hostname is $(random)web-f-2' output | wc -l | grep 1
	grep 'My hostname is $(random)web-g-1' output | wc -l | grep 1
	grep 'My hostname is $(random)web-g-2' output | wc -l | grep 1
	@echo

	@echo "==> Testing with service scale down"
	tutum service scale --sync $(random)web-f 1
	tutum service scale --sync $(random)web-g 1
	rm -f output
	sleep 5
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:web-f.org' $(NODE_FQDN):8004 >> output
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:web-f.org' $(NODE_FQDN):8004 >> output
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:web-g.org' $(NODE_FQDN):8004 >> output
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:web-g.org' $(NODE_FQDN):8004 >> output
	grep 'My hostname is $(random)web-f-1' output | wc -l | grep 2
	grep 'My hostname is $(random)web-g-1' output | wc -l | grep 2
	@echo

	@echo "==> Testing with service stop"
	tutum service stop --sync $(random)web-g
	rm -f output
	sleep 5
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:web-f.org' $(NODE_FQDN):8004 >> output
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:web-f.org' $(NODE_FQDN):8004 >> output
	curl -sL -H 'Host:web-g.org' $(NODE_FQDN):8004 >> output
	curl -sL -H 'Host:web-g.org' $(NODE_FQDN):8004 >> output
	grep 'My hostname is $(random)web-f-1' output | wc -l | grep 2
	grep '503 Service Unavailable' output | wc -l | grep 2
	@echo

	@echo "==> Testing with service start"
	tutum service start --sync $(random)web-g
	rm -f output
	sleep 5
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:web-f.org' $(NODE_FQDN):8004 >> output
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:web-f.org' $(NODE_FQDN):8004 >> output
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:web-g.org' $(NODE_FQDN):8004 >> output
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:web-g.org' $(NODE_FQDN):8004 >> output
	grep 'My hostname is $(random)web-f-1' output | wc -l | grep 2
	grep 'My hostname is $(random)web-g-1' output | wc -l | grep 2
	@echo

	@echo "==> Testing with service terminate"
	tutum service terminate --sync $(random)web-g
	rm -f output
	sleep 5
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:web-f.org' $(NODE_FQDN):8004 >> output
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:web-f.org' $(NODE_FQDN):8004 >> output
	curl -sL -H 'Host:web-g.org' $(NODE_FQDN):8004 >> output
	curl -sL -H 'Host:web-g.org' $(NODE_FQDN):8004 >> output
	grep 'My hostname is $(random)web-f-1' output | wc -l | grep 2
	grep '503 Service Unavailable' output | wc -l | grep 2
	@echo

	@echo "==> Testing with service redeploy"
	tutum service redeploy --sync $(random)web-f
	rm -f output
	sleep 5
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:web-f.org' $(NODE_FQDN):8004 >> output
	curl --retry 10 --retry-delay 5 -sSfL -H 'Host:web-f.org' $(NODE_FQDN):8004 >> output
	curl -sL -H 'Host:web-g.org' $(NODE_FQDN):8004 >> output
	curl -sL -H 'Host:web-g.org' $(NODE_FQDN):8004 >> output
	grep 'My hostname is $(random)web-f-1' output | wc -l | grep 2
	grep '503 Service Unavailable' output | wc -l | grep 2
	@echo

test-unittest:build
	@echo "====== Running unit test ======"
	@echo