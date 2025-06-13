require 'k8s-ruby'
require 'logger'

LOG = Logger.new(STDERR)

NODE_NAME_LABEL = "keen.land/nodeName"
POD_NAME_LABEL = "keen.land/podName"
SELECTOR_LABEL = "keen.land/ds-service-per-pod"
PORT_ANNOTATION = "keen.land/ports"

def needs_updated?(current_state, desired_state, debug: false)
  pp(current_state:, desired_state:) if debug

  if current_state.class != desired_state.class
    LOG.info "different classes" if debug
    return true
  end

  if desired_state.kind_of?(K8s::Resource)
    return needs_updated?(current_state.to_hash, desired_state.to_hash, debug: debug)
  end

  case desired_state.class.to_s
  when "Hash"
    LOG.info "case Hash" if debug
    desired_state.any? do |key, val|
      needs_updated?(current_state[key], val, debug: debug)
    end
  when "Array"
    LOG.info "case Array" if debug
    (0..(desired_state.length - 1)).any? do |i|
      needs_updated?(current_state[i], desired_state[i], debug: debug)
    end
  else
    LOG.info "case Fall through: #{desired_state.class}" if debug
    current_state != desired_state
  end
end

def find_daemonsets(client)
  client.api("apps/v1").resource("daemonsets").list(labelSelector: {SELECTOR_LABEL => true})
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

def refresh_labels_and_services_for_daemonset(client, daemonset)
  ds_name = daemonset.metadata.name
  LOG.info "Refreshing labels and serices for DaemonSet/#{ds_name}"

  label_selector = daemonset.spec.selector.matchLabels.to_hash
  namespace = daemonset.metadata.namespace

  existing_services = client.api("v1").resource("services", namespace: namespace).list(labelSelector: label_selector).map do |svc|
    [svc.metadata.name, svc]
  end.to_h

  client.api("v1").resource("pods", namespace: namespace).list(labelSelector: label_selector).each do |pod|
    new = K8s::Resource.new(pod.to_hash)

    new[:metadata][:labels][NODE_NAME_LABEL] = pod.spec.nodeName
    new[:metadata][:labels][POD_NAME_LABEL] = pod.metadata.name

    if needs_updated?(pod[:metadata][:labels], new[:metadata][:labels])
      client.api("v1").resource("pods", namespace: namespace).update_resource(new)
    end

    ports = parse_ports(pod.metadata.annotations[PORT_ANNOTATION])

    svc = K8s::Resource.new({
      apiVersion: 'v1',
      kind: 'Service',
      metadata: {
        name: "#{ds_name}-#{pod.spec.nodeName}",
        namespace: namespace,
        labels: label_selector,
        ownerReferences: [
          {
            apiVersion: daemonset.apiVersion,
            kind: daemonset.kind,
            name: daemonset.metadata.name,
            uid: daemonset.metadata.uid,
          }
        ]
      },
      spec: {
        type: 'ClusterIP',
        clusterIP: 'None',
        selector: {
          POD_NAME_LABEL => pod.metadata.name,
          NODE_NAME_LABEL => pod.spec.nodeName,
        },
        ports: ports
      },
    })

    next unless needs_updated?(existing_services[svc.metadata.name], svc, debug: false)

    if existing_services.key?(svc.metadata.name)
      LOG.info "updating service #{svc.metadata.name}"
      client.api('v1').resource('services').update_resource(svc)
    else
      LOG.info "creating service #{svc.metadata.name}"
      client.api('v1').resource('services').create_resource(svc)
    end
  end
end

def refresh_all_labels_and_services(client)
  find_daemonsets(client).each do |daemonset|
    refresh_labels_and_services_for_daemonset(client, daemonset)
  end
end

def now
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

shutdown = false
%w[INT TERM QUIT].each do |sig|
  Signal.trap(sig) do
    shutdown = true
  end
end

LOG.info "STARTUP"

config_path = File.expand_path '~/.kube/config'

client = if File.exist?(config_path)
  LOG.info "Reading kube config from #{config_path}"
  K8s::Client.config(
    K8s::Config.load_file(config_path)
  )
else
  LOG.info "Assuming in-cluster kube config"
  K8s::Client.in_cluster_config
end

client.apis(prefetch_resources: true)

last_run = -1

while !shutdown
  if now - last_run >= 30
    refresh_all_labels_and_services(client)
    last_run = now
  end
  sleep 0.1
end

