job "service-logging-cluster" {
    datacenters = ["[[ .datacenter ]]"]
    type = "service"
    [[ range $osType, $osParams := .opensearch]]
    [[ if ne $osParams.count "0"]]
    group "service-opensearch-[[ $osType ]]" {
        constraint {
            attribute = "${node.class}"
            value = "[[ $osParams.nomadClass ]]"
        }
        constraint {
            operator = "distinct_hosts"
            value = "true"
        }
        [[ range $metaType, $metaValue := $osParams.meta ]]
        constraint {
            attribute = "${meta.[[ $metaType ]]}"
            value = "[[ $metaValue ]]"
        }
        [[ end ]]
        count = [[ $osParams.count ]]
        restart {
            attempts    = 3
            delay       = "30s"
            interval    = "5m"
            mode        = "fail"
        }
        update {
            max_parallel = 2
            min_healthy_time = "10s"
            healthy_deadline = "9m"
        }
        [[ range $volume, $dest := $osParams.volumesMount ]]
        volume "[[ $volume ]]" {
            type = "host"
            read_only = false
            source = "[[ $volume ]]"
        }
        [[ end ]]
        network {
            mode = "bridge"
            port "http" {
                static = 9200
                to = 9200
            }
            port "communication" {
                static = 9300
                to = 9300
            }
            port "http_perf_analyzer" {
                static = 9600
                to = 9600
            }
        }
        task "opensearch-[[ $osType ]]" {
            template {
                data = <<EOF
nameserver 172.17.0.1
nameserver {{ env "NOMAD_IP_http" }}
EOF
                destination = "local/resolv.conf"
            }
            driver = "docker"
            kill_timeout = "300s"
            kill_signal = "SIGTERM"
            env {
                OPENSEARCH_JAVA_OPTS = "-Xms1g -Xmx1g"
                DISABLE_SECURITY_PLUGIN = "true"
            }
            template {
                data = <<EOF
cluster:
    name: opensearch-cluster
    [[ if eq $osType "masters" ]]
    initial_master_nodes:
        {{ range service "masters.service-logging-opensearch|any" }}
        - {{ .Address }}{{ end }}
    [[ end ]]
node:
    name: opensearch-[[ $osType ]]-{{ env "NOMAD_ALLOC_INDEX" }}
    [[ if eq $osType "workers" ]]
    roles: [ data, ingest ]
    [[ end ]]
# http:
#    port: {{ env "NOMAD_HOST_PORT_http"}}
#transport:
#    tcp:
#        port: {{ env "NOMAD_HOST_PORT_communication"}}
discovery:
    seed_hosts: 
        {{ range service "masters.service-logging-opensearch|any" }}
        - {{ .Address }}{{ end }}
network:
    host: 0.0.0.0
    publish_host: {{ env "NOMAD_IP_http" }}
bootstrap:
    memory_lock: true
plugins:
    security:
        disabled: true
        ssl:
            http:
                enabled: false
compatibility.override_main_response_version: true
EOF
                destination = "opensearch.yml"
                [[ if eq $osType "masters" ]]
                change_mode = "noop"
                [[ else ]]
                change_mode = "restart"
                [[ end ]]
                perms = "0777"
            }
            [[ range $volume, $dest := $osParams.volumesMount ]]
            volume_mount {
                volume = "[[ $volume ]]"
                destination = "[[ $dest ]]"
                read_only = "false"
            }
            [[ end ]]
            config {
                image = "[[ $osParams.image ]]"
                volumes = [
                    "local/resolv.conf:/etc/resolv.conf",
                    "opensearch.yml:/usr/share/opensearch/config/opensearch.yml"
                ]
                force_pull = false
                ports = ["http"]
                ulimit {
                    memlock = "-1"
                    nofile = "65536"
                    nproc = "65536"
                }
            }
            resources {
                [[ range $type, $value := $osParams.resources ]]
                [[ $type ]]    = [[ $value ]]
                [[ end ]]
            }
        }
        service {
            name = "service-logging-opensearch"
            tags = ["[[ $osType ]]", "[[ $osType ]]-${NOMAD_ALLOC_INDEX}"]
            port = "http"
            connect {
                sidecar_service {
                    tags = ["opensearch-[[ $osType ]]-${NOMAD_ALLOC_INDEX}-sidecar"]
                }
            }
            check {
                type = "http"
                protocol = "http"
                port = "http"
                path = "/"
                interval = "10s"
                timeout = "10s"
            }
        }
    }
    [[ end ]]
    [[ end ]]
    group "service-dashboard" {
        constraint {
            attribute = "${node.class}"
            value = "[[ .dashboard.nomadClass ]]"
        }
        constraint {
            operator = "distinct_hosts"
            value = "true"
        }
        [[ range $metaType, $metaValue := $.dashboard.meta ]]
        constraint {
            attribute = "${meta.[[ $metaType ]]}"
            value = "[[ $metaValue ]]"
        }
        [[ end ]]
        count = "[[ .dashboard.count ]]"
        restart {
            attempts    = 3
            delay       = "30s"
            interval    = "5m"
            mode        = "fail"
        }
        update {
            max_parallel = 1
            min_healthy_time = "10s"
            healthy_deadline = "9m"
        }
        network {
            mode = "bridge"
            port "http" {
                to = 5601
            }
        }
        task "opensearch-dashboards" {
            template {
                data = <<EOF
OPENSEARCH_HOSTS='[{{range $index, $service :=  service "service-logging-opensearch|any"}}{{if ne $index 0}},{{end}}"http://{{$service.Address}}:{{$service.Port}}"{{end}}]'
DISABLE_SECURITY_DASHBOARDS_PLUGIN = "true"
OPENSEARCH_USERNAME="admin"
OPENSEARCH_PASSWORD="admin"
SERVER_BASEPATH="/elk-dashboards"
SERVER_REWRITEBASEPATH="true"
EOF
                destination = "local/file.env"
                env = true
                change_mode = "restart"
            }
            driver = "docker"
            kill_timeout = "300s"
            kill_signal = "SIGTERM"
            config {
                image = "opensearchproject/opensearch-dashboards:1.2.0"
                ulimit {
                    memlock = "-1"
                    nofile = "65536"
                    nproc = "65536"
                }
                ports = ["http"]
            }
            resources {
                [[ range $type, $value := .dashboard.resources ]]
                [[ $type ]]    = [[ $value ]]
                [[ end ]]
            }
        }
        service {
            name = "service-logging-dashboards"
            tags = ["dashboards", "[[ .fabioTagprefix ]]/elk-dashboards"]
            port = "http"
            connect {
                sidecar_service {
                    tags = ["dashboard-${NOMAD_ALLOC_INDEX}-sidecar"]
                }
            }
            check {
                type = "http"
                protocol = "http"
                port = "http"
                path = "/elk-dashboards"
                interval = "10s"
                timeout = "10s"         
            }
        }   
    }
}
