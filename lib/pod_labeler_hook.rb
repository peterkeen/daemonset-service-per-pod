# frozen_string_literal: true

class PodLabelerHook < Hook
  LABEL_SELECTOR = {"keen.land/service-per-pod" => "true"}.freeze
  
  def config
    {
      configVersion: "v1",
      onStartup: 1,
      kubernetes: [
        {
          name: "monitor-pods",
          apiVersion: "v1",
          kind: "Pod",
          labelSelector: {
            matchLabels: LABEL_SELECTOR
          },
          executeHookOnEvent: [ "Added", "Modified" ]
        }
      ]
    }
  end

  def synchronize(context)
    context.flat_map do |event|
      pods = if event[:type] == "Synchronization"
        event[:objects].map { |o| o[:object] }
      else
        [event[:object]]
      end

      pods.filter_map do |pod|
        synchronize_pod(pod)
      end
    end
  end

  def synchronize_pod(pod)
    return if pod.nil?

    {
      operation: "MergePatch",
      apiVersion: pod[:apiVersion],
      kind: pod[:kind],
      namespace: pod[:metadata][:namespace],
      name: pod[:metadata][:name],
      mergePatch: {
        metadata: {
          labels: {
            "keen.land/podName" => pod[:metadata][:name],
            "keen.land/nodeName" => pod[:spec][:nodeName]
          }
        }
      }
    }
  end
end
