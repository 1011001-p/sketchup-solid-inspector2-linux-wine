#-------------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-------------------------------------------------------------------------------

require "json"


module TT::Plugins::SolidInspector2

  class Window < UI::WebDialog

    def initialize(options)
      super(options)

      # For windows that should not be resizable we make sure to set the size
      # after creating the dialog. Otherwise it might be remembering old values
      # and use that instead.
      unless options[:resizable]
        set_size(options[:width], options[:height])
      end

      @events = {}
      @polling = false
      @poll_timer = nil

      # Standard skp: protocol callback (works on native Windows).
      add_action_callback("callback") { |dialog, name|
        # If skp: works, disable polling to avoid duplicate processing.
        stop_polling
        @skp_works = true
        json = get_element_value("SU_BRIDGE")
        if json && json.size > 0
          data = JSON.parse(json)
        else
          data = []
        end
        # Clear the Wine queue since skp: handled it.
        execute_script("_WineAckCallbacks();") rescue nil
        trigger_events(dialog, name, data)
      }

      on("html_ready") { |dialog|
        @on_ready.call(dialog) unless @on_ready.nil?
      }

      on("close_window") { |dialog|
        dialog.close
      }
    end

    # Simplifies calling the JavaScript in the webdialog by taking care of
    # generating the JS command needed to execute it.
    #
    # @param [String] function
    # @param [Mixed] *arguments
    #
    # @return [Nil]
    def call(function, *arguments)
      js_args = arguments.map { |x| x.to_json }.join(", ")
      javascript = "#{function}(#{js_args});"
      execute_script(javascript)
    end

    def on(event, &block)
      return false if block.nil?
      @events[event] ||= []
      @events[event] << block
      true
    end

    def close
      stop_polling
      super
    end

    # Platform neutral method that ensures that window stays on top of the main
    # window on both platforms. Also captures any blocks given and executes it
    # when the HTML DOM is ready.
    def show(&block)
      if visible?
        bring_to_front
      else
        @on_ready = block
        if Sketchup.platform == :platform_osx
          show_modal() {} # Empty block to prevent the block from propagating.
        else
          super() {}
        end
        # Start polling for Wine compatibility after showing the window.
        # If skp: protocol works, polling will be stopped on first native
        # callback received.
        @skp_works = false
        start_polling
      end
    end

    private :show_modal

    private

    # Poll the WINE_BRIDGE hidden input for queued callbacks.
    # JS writes to this element synchronously whenever callback() is called,
    # so Ruby can read it at any time without timing issues.
    def start_polling
      return if @polling
      @polling = true
      @poll_timer = UI.start_timer(0.2, true) {
        poll_js_queue if @polling && visible?
      }
    end

    def stop_polling
      @polling = false
      if @poll_timer
        UI.stop_timer(@poll_timer)
        @poll_timer = nil
      end
    end

    def poll_js_queue
      return unless visible?
      json = get_element_value("WINE_BRIDGE")
      return if json.nil? || json.empty? || json == "[]"
      begin
        messages = JSON.parse(json)
      rescue
        return
      end
      return unless messages.is_a?(Array) && messages.size > 0
      # Acknowledge so JS clears the queue.
      execute_script("_WineAckCallbacks();")
      messages.each do |msg|
        parts = msg.to_s.split("|", 2)
        name = parts[0].to_s
        data_str = parts[1].to_s
        if data_str.size > 0
          begin
            data = JSON.parse(data_str)
          rescue
            data = []
          end
        else
          data = []
        end
        trigger_events(self, name, data)
      end
    rescue => e
      # Silently ignore polling errors (dialog may be closing).
    end

    def trigger_events(dialog, event, data = [])
      if @events[event]
        @events[event].each { |callback|
          callback.call(dialog, data)
        }
        true
      else
        false
      end
    end

    def class_name
      self.class.name.split("::").last
    end

  end # class

end # module TT::Plugins::SolidInspector2
