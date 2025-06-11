# frozen_string_literal: true

require 'json'

class Hook
  def config
    raise NotImplementedError
  end

  def synchronize(context)
    raise NotImplementedError
  end

  def run(args)
    if args[0] == "--config"
      puts config.to_json
    else
      raw_context = File.read(ENV.fetch("BINDING_CONTEXT"))

      context = JSON.parse(raw_context, symbolize_names: true)
      result = synchronize(context)

      File.open(ENV.fetch("KUBERNETES_PATCH_PATH"), "w+") do |f|
        f.write(result.to_json)
      end
    end
  end
end
