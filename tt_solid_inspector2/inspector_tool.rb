#-------------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-------------------------------------------------------------------------------

require "set"
require "json"

module TT::Plugins::SolidInspector2

  require File.join(PATH, "error_finder.rb")
  require File.join(PATH, "geometry.rb")
  require File.join(PATH, "heisenbug.rb")
  require File.join(PATH, "instance.rb")
  require File.join(PATH, "key_codes.rb")
  require File.join(PATH, "legend.rb")
  require File.join(PATH, "execution.rb")

  unless defined?(OVERLAY)
    OVERLAY = if defined?(Sketchup::Overlay)
      Sketchup::Overlay
    else
      require 'tt_solid_inspector2/mock_overlay'
      MockOverlay
    end
  end

  class InspectorTool < OVERLAY

    OVERLAY_ID = 'thomthom.solidinspector'.freeze

    include KeyCodes

    DIALOG_HTML = <<-'HTML'
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }
html, body { font-family: "Segoe UI", Arial, sans-serif; font-size: 13px;
  color: #444; background: #fff; height: 100%; overflow: hidden; cursor: default;
  user-select: none; -webkit-user-select: none; }
#header { position: fixed; top: 0; left: 0; right: 0; height: 52px;
  padding: 10px 10px 10px 52px; border-bottom: 5px solid #a00;
  background: #c33; color: #fff; font-size: 1.5em; line-height: 32px; z-index: 100; }
#header img { position: absolute; left: 10px; top: 10px; }
#content { position: fixed; top: 57px; bottom: 53px; left: 0; right: 0; overflow: auto; }
#footer { position: fixed; bottom: 0; left: 0; right: 0; border-top: 1px solid #ccc;
  background: #eee; padding: 10px; text-align: right; z-index: 50; }
button { height: 32px; min-width: 90px; color: #555; background: #f7f7f7;
  border: 1px solid #bbb; border-radius: 3px; cursor: pointer; }
button:hover { box-shadow: inset 0 0 10px rgba(0,0,0,0.2); }
button.default { color: #fff; background: #c33; border-color: #a00; }
button.default:hover { box-shadow: inset 0 0 10px rgba(0,0,0,0.5); }
button.default:disabled { background: #fee; border-color: #caa; color: #caa; cursor: default; }
button.default:disabled:hover { box-shadow: none; }
#no-errors { color: #999; font-size: 1.5em; text-align: center; line-height: 1.5em;
  padding: 1em; position: absolute; top: 0; bottom: 0; left: 0; right: 0; }
#smiley { margin: 1em; font-size: 2em; }
.error-group { background: #eee; border-bottom: 1px solid #ccc;
  padding: 10px 110px 10px 10px; position: relative; min-height: 65px; cursor: pointer; }
.error-group:hover { background: #e4e4e4; }
.error-group.selected { background: #ffe0d7; }
.error-group .title { font-weight: bold; margin-bottom: 5px; position: relative; z-index: 20; }
.error-group .count { position: absolute; z-index: 10; left: 10px; top: 25px;
  font-family: Arial, sans-serif; font-size: 50px; font-weight: bold; color: #aaa; }
.error-group .description { position: absolute; left: 10px; right: 110px; z-index: 40;
  color: #fff; background: rgba(0,0,0,0.8); padding: 10px; border-radius: 5px; display: none; }
.error-group .expand_info { display: inline-block; position: absolute; top: 12px;
  right: 110px; z-index: 25; text-decoration: none; font-weight: bold; border: none; cursor: pointer; }
.error-group .fix { position: absolute; right: 10px; top: 10px; z-index: 30; }
</style>
</head>
<body>
<div id="header">Solid Inspector²</div>
<div id="content"></div>
<div id="footer">
  <button id="fix-all" class="default" disabled>Fix All</button>
</div>
<script>
document.getElementById('fix-all').addEventListener('click', function() {
  sketchup.fix_all();
});
document.getElementById('content').addEventListener('click', function(e) {
  var group = e.target.closest('.error-group');
  if (!group) {
    document.querySelectorAll('.error-group').forEach(function(el) { el.classList.remove('selected'); });
    sketchup.select_group('');
    return;
  }
  // Check if clicked on expand_info
  if (e.target.closest('.expand_info')) {
    var desc = group.querySelector('.description');
    desc.style.display = desc.style.display === 'block' ? 'none' : 'block';
    return;
  }
  // Check if clicked on fix button
  if (e.target.closest('.fix')) {
    sketchup.fix_group(group.dataset.type);
    return;
  }
  // Select/highlight this error group
  document.querySelectorAll('.error-group').forEach(function(el) { el.classList.remove('selected'); });
  group.classList.add('selected');
  sketchup.select_group(group.dataset.type);
});

function list_errors(errors_json) {
  var errors = JSON.parse(errors_json);
  var content = document.getElementById('content');
  content.innerHTML = '';
  var keys = Object.keys(errors);
  if (keys.length === 0) {
    content.innerHTML = "<div id='no-errors'>No Errors<br>Everything is shiny<div id='smiley'>:)</div></div>";
    document.getElementById('fix-all').disabled = true;
    return;
  }
  var has_fixable = false;
  keys.forEach(function(key) {
    var g = errors[key];
    var fix_label = g.fixable ? 'Fix' : 'Info';
    if (g.fixable) has_fixable = true;
    var html = '<div class="error-group" data-type="' + g.type + '">' +
      '<div class="title">' + g.name + '</div>' +
      '<a class="expand_info" title="Click for help">&#x2753;</a>' +
      '<div class="count">' + g.count + '</div>' +
      '<div class="description">' + g.description + '</div>' +
      '<button class="fix">' + fix_label + '</button></div>';
    content.insertAdjacentHTML('beforeend', html);
  });
  document.getElementById('fix-all').disabled = !has_fixable;
}

// Notify Ruby that the page is ready so it can push initial data.
setTimeout(function() { sketchup.ready(); }, 100);
</script>
</body>
</html>
HTML

    def initialize(overlay: false)
      super(OVERLAY_ID, 'Solid Inspection')

      @overlay = overlay

      @errors = []
      @current_error = 0
      @filtered_errors = nil

      @legends = []
      @screen_legends = nil

      @entities = nil
      @instance_path = nil
      @transformation = nil

      @dialog = nil
      @deactivating = false
      nil
    end

    def running_as_overlay?
      @overlay
    end

    def start
      activate
    end

    def stop
      deactivate(Sketchup.active_model.active_view)
    end

    def activate
      @deactivating = false

      unless running_as_overlay?
        create_dialog unless @dialog
        @dialog.show
      end

      model = Sketchup.active_model
      model.active_view.invalidate
      update_ui

      start_observing_app
      start_observing_model(model)

      analyze if running_as_overlay?
      nil
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    end

    def deactivate(view)
      @deactivating = true
      if @dialog
        @dialog.close
      end
      view.invalidate if view

      stop_observing_model(Sketchup.active_model)
      stop_observing_app
      nil
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    end

    def resume(view)
      @screen_legends = nil
      view.invalidate
      update_ui
      nil
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    end

    def onMouseMove(flags, x, y, view)
      return false if running_as_overlay?
      if @screen_legends
        point = Geom::Point3d.new(x, y, 0)
        legend = @screen_legends.find { |legend| legend.mouse_over?(point, view) }
        view.tooltip = legend ? legend.tooltip : ""
      end
      nil
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    end

    def onLButtonUp(flags, x, y, view)
      return false if running_as_overlay?

      if @screen_legends
        point = Geom::Point3d.new(x, y, 0)
        legend = @screen_legends.find { |legend| legend.mouse_over?(point, view) }
        if legend
          if legend.is_a?(LegendGroup)
            error = legend.legends.first.error
          else
            legend.error
          end
          index = filtered_errors.find_index(error)
          if index
            @current_error = index
            view.invalidate
            return nil
          end
        end
      end

      ph = view.pick_helper
      ph.do_pick(x, y)
      view.model.selection.clear
      if Instance.is?(ph.best_picked)
        view.model.selection.add(ph.best_picked)
      end
      analyze
      view.invalidate
      nil
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    end

    def onKeyUp(key, repeat, flags, view)
      return if @errors.empty?

      shift = flags & CONSTRAIN_MODIFIER_MASK == CONSTRAIN_MODIFIER_MASK
      errors = filtered_errors

      if key == KEY_TAB
        if @current_error.nil?
          @current_error = 0
        elsif shift
          @current_error = (@current_error - 1) % errors.size
        else
          @current_error = (@current_error + 1) % errors.size
        end
      end

      if key == VK_UP || key == VK_RIGHT
        @current_error = @current_error.nil? ? 0 : (@current_error + 1) % errors.size
      end
      if key == VK_DOWN || key == VK_LEFT
        @current_error = @current_error.nil? ? 0 : (@current_error - 1) % errors.size
      end

      if (key == KEY_RETURN || key == KEY_TAB) && @current_error
        zoom_to_error(view)
      end

      deselect_tool if key == KEY_ESCAPE

      view.invalidate
      false
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    end

    if Sketchup.version.to_i < 15
      def getMenu(menu)
        context_menu(menu)
      rescue Exception => exception
        ERROR_REPORTER.handle(exception)
      end
    else
      def getMenu(menu, flags, x, y, view)
        context_menu(menu, flags, x, y, view)
      rescue Exception => exception
        ERROR_REPORTER.handle(exception)
      end
    end

    def draw(view)
      filtered_errors.each { |error|
        error.draw(view, @transformation, texture_id: @texture_id)
      }
      draw_circle_around_current_error(view)

      if @screen_legends.nil?
        start_time = Time.now
        @screen_legends = merge_close_legends(@legends, view)
        @legend_time = Time.now - start_time
      end
      if Settings.debug_mode? && Settings.debug_legend_merge? && @legend_time
        view.draw_text([20, 20, 0], "Legend Merge: #{@legend_time}")
      end
      @screen_legends.each { |legend| legend.draw(view) }

      view.line_stipple = ''
      view.line_width = 1
      nil
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    end

    def onSelectionAdded(selection, entity)
      reanalyze
    end
    def onSelectionBulkChange(selection)
      reanalyze
    end
    def onSelectionCleared(selection)
      reanalyze
    end
    def onSelectionRemoved(selection, entity)
      reanalyze
    end
    def onSelectedRemoved(selection, entity)
      onSelectionRemoved(selection, entity)
    end
    def onTransactionCommit(model)
      reanalyze
    end
    def onTransactionEmpty(model)
      reanalyze
    end
    def onTransactionRedo(model)
      reanalyze
    end
    def onTransactionUndo(model)
      reanalyze
    end
    def onNewModel(model)
      start_observing_model(model)
    end
    def onOpenModel(model)
      start_observing_model(model)
    end

    private

    def start_observing_app
      return unless Sketchup.platform == :platform_win
      Sketchup.remove_observer(self)
      Sketchup.add_observer(self)
    end

    def stop_observing_app
      return unless Sketchup.platform == :platform_win
      Sketchup.remove_observer(self)
    end

    def start_observing_model(model)
      model.add_observer(self)
    end

    def stop_observing_model(model)
      return if model.nil?
      model.remove_observer(self)
    end

    def reanalyze
      @reanalyze ||= Execution::Debounce.new(0.05)
      @reanalyze.call do
        analyze
        Sketchup.active_model.active_view.invalidate
      end
    end

    def analyze
      model = Sketchup.active_model
      entities = model.active_entities
      instance_path = model.active_path || []
      transformation = Geom::Transformation.new

      unless model.selection.empty?
        instance = model.selection.find { |entity| Instance.is?(entity) }
        if instance
          definition = Instance.definition(instance)
          entities = definition.entities
          instance_path << instance
          transformation = instance.transformation
        end
      end

      @filtered_errors = nil
      @current_error = nil
      @errors = ErrorFinder.find_errors(entities)
      @entities = entities
      @instance_path = instance_path
      @transformation = transformation

      update_dialog
      update_legends
      update_ui
      nil
    rescue HeisenBug => error
      HeisenbugDialog.new.show
      ERROR_REPORTER.handle(error)
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    end

    def create_dialog
      @dialog = UI::HtmlDialog.new(
        :dialog_title => PLUGIN_NAME,
        :preferences_key => "#{PLUGIN_ID}_InspectorWindow",
        :scrollable => false,
        :resizable => true,
        :width => 400,
        :height => 600,
        :left => 200,
        :top => 200,
        :min_width => 400,
        :min_height => 250,
        :style => UI::HtmlDialog::STYLE_DIALOG
      )

      @dialog.set_html(DIALOG_HTML)

      @dialog.add_action_callback("fix_all") { |action_context|
        fix_all
        Sketchup.active_model.active_view.invalidate
      }

      @dialog.add_action_callback("fix_group") { |action_context, type|
        fix_group(type)
        Sketchup.active_model.active_view.invalidate
      }

      @dialog.add_action_callback("select_group") { |action_context, type|
        select_group(type.to_s.empty? ? nil : type)
        Sketchup.active_model.active_view.invalidate
      }

      @dialog.set_on_closed {
        unless @deactivating
          Sketchup.active_model.select_tool(nil)
        end
      }

      # When dialog finishes loading, push current errors.
      @dialog.add_action_callback("ready") { |action_context|
        analyze
        Sketchup.active_model.active_view.invalidate
      }

      @dialog
    end

    def update_dialog
      return unless @dialog && @dialog.visible?
      grouped = group_errors(@errors)
      # Build a simpler hash for JSON serialization.
      data = {}
      grouped.each do |klass, info|
        data[info[:type]] = {
          :type => info[:type],
          :name => info[:name],
          :description => info[:description],
          :fixable => info[:fixable],
          :count => info[:errors].size
        }
      end
      json = data.to_json.gsub("'", "\\\\'")
      @dialog.execute_script("list_errors('#{json}');")
    rescue => e
      # Dialog may not be ready yet.
    end

    def deselect_tool
      Sketchup.active_model.select_tool(nil)
    end

    def context_menu(menu, flags = nil, x = nil, y = nil, view = nil)
      view ||= Sketchup.active_model.active_view
      can_select = @entities == view.model.active_entities

      message = "Only entities in the active context can be selected. Please "\
        "open the group or component you are inspecting to be able to select "\
        "entities."

      if @screen_legends && x && y
        point = Geom::Point3d.new(x, y, 0)
        legend = @screen_legends.find { |legend| legend.mouse_over?(point, view) }
        if legend
          return UI.messagebox(message) unless can_select
          menu.add_item("Select Entities") {
            entities = Set.new
            if legend.is_a?(LegendGroup)
              legend.legends.each { |l| entities.merge(l.error.entities) }
            else
              entities.merge(legend.error.entities)
            end
            view.model.selection.clear
            view.model.selection.add(entities.to_a)
            view.invalidate
          }
          return true
        end
      end

      if @errors.size > 0
        menu.add_item("Select Entities from All Errors") {
          return UI.messagebox(message) unless can_select
          entities = Set.new
          @errors.each { |error| entities.merge(error.entities) }
          view.model.selection.clear
          view.model.selection.add(entities.to_a)
          view.invalidate
        }
      end

      groups = group_errors(@errors)
      if groups.size > 0
        groups.each { |klass, data|
          menu.add_item("Select #{klass.display_name}") {
            return UI.messagebox(message) unless can_select
            entities = Set.new
            data[:errors].each { |error| entities.merge(error.entities) }
            view.model.selection.clear
            view.model.selection.add(entities.to_a)
            view.invalidate
          }
        }
      end

      menu.add_separator if @errors.size > 0

      item = menu.add_item("Detect Short Edges") {
        Settings.detect_short_edges = !Settings.detect_short_edges?
        reanalyze_short_edges
        view.invalidate
      }
      menu.set_validation_proc(item) {
        Settings.detect_short_edges? ? MF_CHECKED : MF_UNCHECKED
      }

      threshold = Settings.short_edge_threshold
      item = menu.add_item("Short Edge Threshold: #{threshold}") {
        prompts = ["Edge Length"]
        defaults = [threshold]
        result = UI.inputbox(prompts, defaults, "Short Edge Threshold")
        if result
          Settings.short_edge_threshold = result[0]
          reanalyze_short_edges
          view.invalidate
        end
      }
      menu.set_validation_proc(item) {
        Settings.detect_short_edges? ? MF_ENABLED : MF_GRAYED
      }

      if Settings.debug_mode?
        menu.add_separator
        item = menu.add_item("Debug Legend Merge Performance") {
          Settings.debug_legend_merge = !Settings.debug_legend_merge?
          view.invalidate
        }
        menu.set_validation_proc(item) {
          Settings.debug_legend_merge? ? MF_CHECKED : MF_UNCHECKED
        }
        item = menu.add_item("Debug Error Report") {
          Settings.debug_error_report = !Settings.debug_error_report?
          view.invalidate
        }
        menu.set_validation_proc(item) {
          Settings.debug_error_report? ? MF_CHECKED : MF_UNCHECKED
        }
        item = menu.add_item("Debug Color Internal Face") {
          Settings.debug_color_internal_faces = !Settings.debug_color_internal_faces?
          view.invalidate
        }
        menu.set_validation_proc(item) {
          Settings.debug_color_internal_faces? ? MF_CHECKED : MF_UNCHECKED
        }
      end

      true
    end

    def draw_circle_around_current_error(view)
      return false if @current_error.nil?
      return false if filtered_errors.empty?

      error = filtered_errors[@current_error]
      points = Set.new
      error.entities.each { |entity|
        if entity.respond_to?(:vertices)
          points.merge(entity.vertices)
        else
          bounds = entity.bounds
          points.merge((0..7).map { |i| bounds.corner(i) })
        end
      }

      screen_points = points.to_a.map { |point|
        point = point.position if point.is_a?(Sketchup::Vertex)
        sp = view.screen_coords(point.transform(@transformation))
        sp.z = 0
        sp
      }

      bounds = Geom::BoundingBox.new
      bounds.add(screen_points)
      diameter = [bounds.corner(BB_LEFT_FRONT_BOTTOM).distance(bounds.corner(BB_RIGHT_BACK_TOP)), 20].max
      circle = Geometry.circle2d(bounds.center, X_AXIS, diameter / 2, 64)

      view.line_stipple = ''
      view.line_width = 2
      view.drawing_color = SolidErrors::SolidError::ERROR_COLOR_EDGE
      view.draw2d(GL_LINE_LOOP, circle)
      true
    end

    def filtered_errors
      @filtered_errors.nil? ? @errors : @errors.grep(@filtered_errors)
    end

    def fix_all
      ErrorFinder.fix_errors(@errors, @entities)
      analyze
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    end

    def fix_group(type)
      error_klass = SolidErrors.const_get(type)
      errors = @errors.select { |error| error.is_a?(error_klass) }
      ErrorFinder.fix_errors(errors, @entities)
      analyze
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    end

    def select_group(type)
      if type.nil?
        @filtered_errors = nil
      else
        @filtered_errors = SolidErrors.const_get(type)
      end
      @current_error = nil
      Sketchup.active_model.active_view.invalidate
      nil
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    end

    def group_errors(errors)
      groups = {}
      errors.each { |error|
        unless groups.key?(error.class)
          groups[error.class] = {
            :type        => error.class.type_name,
            :name        => error.class.display_name,
            :description => error.class.description,
            :fixable     => error.fixable?,
            :errors      => []
          }
        end
        groups[error.class][:errors] << error
      }
      groups
    end

    def reanalyze_short_edges
      @errors.reject! { |error| error.is_a?(SolidErrors::ShortEdge) }
      if Settings.detect_short_edges?
        ErrorFinder.find_short_edges(@entities) { |edge|
          @errors << SolidErrors::ShortEdge.new(edge)
        }
      end
      update_legends
      update_dialog
      nil
    end

    def update_legends
      @legends = @errors.grep(SolidErrors::ShortEdge).map { |error|
        ShortEdgeLegend.new(error, @transformation)
      }
      @screen_legends = nil
    end

    def update_ui
      Sketchup.status_text = "Click on solids to inspect. Use arrow keys to cycle between "\
        "errors. Press Return to zoom to error. Press Tab/Shift+Tab to cycle "\
        "though errors and zoom. Right-click for more options."
      nil
    end

    def zoom_to_error(view)
      error = filtered_errors[@current_error]
      view.zoom(error.entities)
      camera = view.camera
      point = camera.target
      offset = view.pixels_to_model(1000, point)
      offset_point = point.offset(camera.direction.reverse, offset)
      vector = point.vector_to(offset_point)
      tr = vector.valid? ? @transformation * Geom::Transformation.new(vector) : @transformation

      view.camera.set(camera.eye.transform(tr), camera.target.transform(tr), camera.up.transform(tr))
      @screen_legends = nil
      nil
    end

    def merge_close_legends(legends, view)
      merged = []
      legends.each { |legend|
        next unless legend.on_screen?(view)
        group = merged.find { |l| legend.intersect?(l, view) }
        if group
          group.add_legend(legend)
        else
          merged << LegendGroup.new(legend)
        end
      }
      merged
    end

  end # class InspectorTool
end # module TT::Plugins::SolidInspector2
