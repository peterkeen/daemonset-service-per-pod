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
            f.write(result.to_yaml(stringify_names: true))
          end
        end
      end
    end
  end
end
