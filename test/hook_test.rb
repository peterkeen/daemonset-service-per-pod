# frozen_string_literal: true

require 'tempfile'
require 'hook'

class HookTest < ::Minitest::Test
  class TestHook < ::Hook
    def initialize(sync_output=nil)
      @sync_output = sync_output
      super()
    end

    def config
      {
        configVersion: "v1",
        kubernetes: [
          {
            name: "test-thing",
            apiVersion: "v1",
            kind: "Pod",
            executeHookOnEvent: [ "Added", "Modified" ]
          }
        ]
      }
    end

    def synchronize(context)
      @sync_output
    end

    attr_reader :output
    def puts(str)
      @output ||= []
      @output << str
    end
  end

  def test_config
    hook = TestHook.new
    hook.run(["--config"])

    expected = <<~HERE
    ---
    configVersion: v1
    kubernetes:
    - name: test-thing
      apiVersion: v1
      kind: Pod
      executeHookOnEvent:
      - Added
      - Modified
    HERE

    assert_equal expected, hook.output[0]
  end

  def test_synchronize__nil
    binding_file = Tempfile.new
    binding_file.write({"binding":"onStartup"}.to_json)
    binding_file.rewind

    ENV['BINDING_CONTEXT_PATH'] = binding_file.path

    patch_file = Tempfile.new
    ENV['KUBERNETES_PATCH_PATH'] = patch_file.path

    hook = TestHook.new
    hook.run([])

    patch_file.rewind
    assert_equal "", patch_file.read
  end

  def test_synchronize__empty
    binding_file = Tempfile.new
    binding_file.write({"binding":"onStartup"}.to_json)
    binding_file.rewind

    ENV['BINDING_CONTEXT_PATH'] = binding_file.path

    patch_file = Tempfile.new
    ENV['KUBERNETES_PATCH_PATH'] = patch_file.path

    hook = TestHook.new([])
    hook.run([])

    patch_file.rewind
    assert_equal "", patch_file.read
  end  

  def test_synchronize__one_item
    binding_file = Tempfile.new
    binding_file.write({"binding":"onStartup"}.to_json)
    binding_file.rewind

    ENV['BINDING_CONTEXT_PATH'] = binding_file.path

    patch_file = Tempfile.new
    ENV['KUBERNETES_PATCH_PATH'] = patch_file.path

    hook = TestHook.new([{hi: "there"}])
    hook.run([])

    expected = <<~HERE
    ---
    hi: there
    HERE

    patch_file.rewind
    assert_equal expected, patch_file.read
  end

  def test_synchronize__two_item
    binding_file = Tempfile.new
    binding_file.write({"binding":"onStartup"}.to_json)
    binding_file.rewind

    ENV['BINDING_CONTEXT_PATH'] = binding_file.path

    patch_file = Tempfile.new
    ENV['KUBERNETES_PATCH_PATH'] = patch_file.path

    hook = TestHook.new([{hi: "there"}, {foo: 123}])
    hook.run([])

    expected = <<~HERE
    ---
    hi: there
    ---
    foo: 123
    HERE

    patch_file.rewind
    assert_equal expected, patch_file.read
  end    
end
