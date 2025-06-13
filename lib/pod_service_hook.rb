# frozen_string_literal: true

class PodServiceHook < Hook
  LABEL_SELECTOR = {"keen.land/service-per-pod" => "true"}.freeze
  PORT_ANNOTATION = "keen.land/ports"

  def config
    {
      configVersion: "v1",
      onStartup: 1,
      kubernetes: [
        {
          name: "monitor_pods",
          group: "pod-per-service",
          apiVersion: "v1",
          kind: "Pod",
          executeHookOnEvent: [ "Added", "Modified", "Deleted" ],
          labelSelector: {
            matchLabels: LABEL_SELECTOR
          }
        },
        {
          name: "monitor_services",
          group: "pod-per-service",
          apiVersion: "v1",
          kind: "Service",
          executeHookOnEvent: [ "Added", "Modified", "Deleted" ],
          labelSelector: {
            matchLabels: LABEL_SELECTOR
          },
        },
      ]
    }
  end

  def synchronize(context)
    active_services = []
    known_services = {}

    context.each do |event|
      (event.dig(:snapshots, :monitor_services) || []).each do |service_wrapper|
        svc = K8s::Resource.new(service_wrapper[:object])
        known_services[[svc.metadata.namespace, svc.metadata.name]] = svc
      end

      (event.dig(:snapshots, :monitor_pods) || []).each do |pod_wrapper|
        pod = K8s::Resource.new(pod_wrapper[:object])
        svc = build_service_from_pod(pod)
        svc_key = [svc.metadata.namespace, svc.metadata.name]
        active_services << svc_key

        if needs_updated?(known_services[svc_key], svc)
          if known_services.key?(svc_key)
            update_resource(svc)
          else
            create_resource(svc)
          end
        end
      end

      known_services.keys.each do |svc|
        unless active_services.include?(svc)
          delete_resource(known_services[svc])
        end
      end
    end

    nil
  end

  def build_service_from_pod(pod)
    podname = pod.metadata.name
    namespace = pod.metadata.namespace
    nodename = pod.spec.nodeName

    ds_name = podname.split("-")[0..-2].join("-")

    ports = parse_ports(pod.metadata.annotations[PORT_ANNOTATION] || "")

    K8s::Resource.new({
      apiVersion: 'v1',
      kind: 'Service',
      metadata: {
        name: "#{ds_name}-#{nodename}",
        namespace: namespace,
        labels: LABEL_SELECTOR,
      },
      spec: {
        type: 'ClusterIP',
        clusterIP: 'None',
        selector: {
          "keen.land/podName" => podname,
        },
        ports: ports
      },
    })
  end

  def parse_ports(raw_ports)
    port_list = raw_ports.split(/,/)
    port_list.map { |port| parse_port(port) }
  end

  def parse_port(raw_port)
    name, port, target_port = raw_port.split(":")
    target_port ||= port
    protocol = "TCP"

    if target_port.end_with?("/udp")
      protocol = "UDP"
      target_port = target_port.gsub("/udp", "")
      port = port.gsub("/udp", "")
    end

    {
      protocol: protocol,
      port: port.to_i,
      targetPort: target_port.to_i,
      name: name,
    }
  end
end
