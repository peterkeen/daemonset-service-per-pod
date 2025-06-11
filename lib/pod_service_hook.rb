# frozen_string_literal: true

class PodServiceHook < Hook
  LABEL_SELECTOR = {"keen.land/pod-per-service" => "true"}.freeze
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
    updates = []
    active_services = []

    context.each do |event|
      (event.dig(:snapshots, :monitor_pods) || []).each do |pod|
        service = create_service_from_pod(pod[:object])
        active_services = []
        updates << service
        active_services << [service.dig(:object, :metadata, :name), service.dig(:object, :metadata, :namespace)]
      end

      (event.dig(:snapshots, :monitor_services) || []).each do |service|
        unless active_services.include?([service.dig(:object, :metadata, :name), service.dig(:object, :metadata, :namespace)])
          updates << delete_service(service[:object])
        end
      end
    end

    updates
  end

  def create_service_from_pod(pod)
    podname = pod[:metadata][:name]
    namespace = pod[:metadata][:namespace]
    nodename = pod[:spec][:nodeName]

    ds_name = podname.split("-")[0..-2].join("-")

    ports = parse_ports(pod.dig(:metadata, :annotations, PORT_ANNOTATION.to_sym) || "")

    {
      operation: "CreateOrUpdate",
      object: {
        apiVersion: 'v1',
        kind: 'Service',
        metadata: {
          name: "#{ds_name}-#{nodename}",
          namespace: namespace,
          labels: LABEL_SELECTOR
        },
        spec: {
          type: 'ClusterIP',
          clusterIP: 'None',
          selector: {
            "keen.land/podName" => podname
          },
          ports: ports
        }
      }
    }
  end

  def delete_service(service)
    {
      operation: "DeleteInBackground",
      apiVersion: service[:apiVersion],
      kind: service[:kind],
      namespace: service[:metadata][:namespace],
      name: service[:metadata][:name],
    }
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
