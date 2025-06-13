class PodServiceHookTest < ::Minitest::Test
  def test_config
    expected_config = {
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
            matchLabels: {
              "keen.land/service-per-pod" => "true"
            }
          }
        },
        {
          name: "monitor_services",
          group: "pod-per-service",
          apiVersion: "v1",
          kind: "Service",
          executeHookOnEvent: [ "Added", "Modified", "Deleted" ],
          labelSelector: {
            matchLabels: {
              "keen.land/service-per-pod" => "true"
            }
          },
        },
      ]
    }

    assert_equal(expected_config, PodServiceHook.new.config)
  end

  def test_synchronize__add_service
    context = [
      {
        type: "Group",
        snapshots: {
          monitor_pods: [{
          object: {
             apiVersion: "v1",
              kind: "Pod",
              metadata: {
                name: "test-pod-abc123",
                namespace: "test-ns",
                labels: {
                  "keen.land/service-per-pod" => "true"
                },
                annotations: {
                  :"keen.land/ports" => "web:8080"
                }
              },
              spec: {
                nodeName: "some-node"
              }
            }
          }]
        }
      }
    ]

    expected_service = {
      apiVersion: "v1",
      kind: "Service",
      metadata: {
        name: "test-pod-some-node",
        namespace: "test-ns",
        labels: {
          "keen.land/service-per-pod": "true"
        }
      },
      spec: {
        type: "ClusterIP",
        clusterIP: "None",
        selector: {
          "keen.land/podName": "test-pod-abc123"
        },
        ports: [
          {
            name: "web",
            port: 8080,
            targetPort: 8080,
            protocol: "TCP",
          }
        ]
      }
    }

    hook = PodServiceHook.new
    mock_client = Minitest::Mock.new
    mock_client.expect(:create_resource, nil) do |service|
      assert_equal(expected_service, service.to_hash)
    end

    hook.stub(:client, mock_client) do
      hook.synchronize(context)
    end
  end

  def test_synchronize__delete_service
    context = [
      {
        type: "Group",
        snapshots: {
          monitor_services: [
            {
              object: {
                apiVersion: "v1",
                kind: "Service",
                metadata: {
                  name: "test-pod-some-node",
                  namespace: "test-ns",
                  labels: {
                    "keen.land/service-per-pod" => "true"
                  },
                },
              }
            }
          ]
        }
      }
    ]

    expected_delete = {
      apiVersion: "v1",
      kind: "Service",
      metadata: {
        namespace: "test-ns",
        name: "test-pod-some-node",
        labels: {
          "keen.land/service-per-pod": "true"
        }
      }
    }

    hook = PodServiceHook.new
    mock_client = Minitest::Mock.new
    mock_client.expect(:delete_resource, nil) do |service|
      assert_equal(expected_delete, service.to_hash)
    end

    hook.stub(:client, mock_client) do
      hook.synchronize(context)
    end
  end
end
