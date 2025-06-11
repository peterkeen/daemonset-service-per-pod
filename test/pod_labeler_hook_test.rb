class PodLabelerHookTest < ::Minitest::Test
  def test_config
    expected_config = {
      configVersion: "v1",
      onStartup: 1,
      kubernetes: [
        {
          name: "monitor-pods",
          apiVersion: "v1",
          kind: "Pod",
          executeHookOnEvent: [ "Added", "Modified" ]
        }
      ]
    }

    assert_equal(expected_config, PodLabelerHook.new.config)
  end

  def test_synchronize__works_with_synchronization_event
    context = [
      {
        type: "Synchronization",
        objects: [
          object: {
            apiVersion: "v1",
            kind: "Pod",
            metadata: {
              name: "test-pod",
              namespace: "test-ns",
            },
            spec: {
              nodeName: "some-node"
            }
          }
        ]
      }
    ]

    expected_patch = [
      {
        operation: "MergePatch",
        apiVersion: "v1",
        kind: "Pod",
        namespace: "test-ns",
        name: "test-pod",
        mergePatch: {
          metadata: {
            labels: {
              "keen.land/podName" => "test-pod",
              "keen.land/nodeName" => "some-node"
            }
          }
        }
      }
    ]

    assert_equal(expected_patch, PodLabelerHook.new.synchronize(context))
  end

  def test_synchronize__works_with_created_event
    context = [
      {
        type: "Created",
        object: {
          apiVersion: "v1",
          kind: "Pod",
          metadata: {
            name: "test-pod",
            namespace: "test-ns",
          },
          spec: {
            nodeName: "some-node"
          }
        }
      }
    ]

    expected_patch = [
      {
        operation: "MergePatch",
        apiVersion: "v1",
        kind: "Pod",
        namespace: "test-ns",
        name: "test-pod",
        mergePatch: {
          metadata: {
            labels: {
              "keen.land/podName" => "test-pod",
              "keen.land/nodeName" => "some-node"
            }
          }
        }
      }
    ]

    assert_equal(expected_patch, PodLabelerHook.new.synchronize(context))    
  end
end
