# frozen_string_literal: true

require 'yaml'

class Hook
  def config
    raise NotImplementedError
  end

  def synchronize(context)
    raise NotImplementedError
  end

  def run(args)
    if args[0] == "--config"
      puts config.to_yaml(stringify_names: true)
    else
      raw_context = File.read(ENV.fetch("BINDING_CONTEXT_PATH"))

      context = JSON.parse(raw_context, symbolize_names: true)
      result = synchronize(context)

      if !result.nil? && result.length > 0
        File.open(ENV.fetch("KUBERNETES_PATCH_PATH"), "w+") do |f|
          result.each do |r|
            f.write(r.to_yaml(stringify_names: true))
          end
        end
      end
    end
  end

  def client
    return @client if @client

    @client = K8s::Client.autoconfig
  end

  def create_resource(resource)
    client.create_resource(resource)
  end

  def update_resource(resource)
    client.update_resource(resource)
  end

  def delete_resource(resource)
    client.delete_resource(resource)
  end

  def needs_updated?(current_state, desired_state)
    if current_state.class != desired_state.class
      return true
    end

    if desired_state.kind_of?(K8s::Resource)
      return needs_updated?(current_state.to_hash, desired_state.to_hash)
    end

    case desired_state.class.to_s
    when "Hash"
      desired_state.any? do |key, val|
        needs_updated?(current_state[key], val)
      end
    when "Array"
      (0..(desired_state.length - 1)).any? do |i|
        needs_updated?(current_state[i], desired_state[i])
      end
    else
      current_state != desired_state
    end
  end

end
