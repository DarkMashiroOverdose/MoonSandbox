/// ------------------------
/// UI实体的定义与更新
/// ------------------------
//每个作战单位和它对应的选中框
let unit_to_selection_box: Map[@system.Entity, @system.Entity] = Map::new()
fn attach_selection_box(
  parent_unit: @system.Entity, 
  parent_pos: @math.Vec2D, 
  parent_dims: @math.Vec2D,
  parent_team: Team,
) -> @system.Entity {
  let new_selection_box = @system.Entity::new()
  let box_size = parent_dims + @math.Vec2D(4.0, 4.0) // 选择框比单位稍大
  //初始化选择框的位置
  @position.positions.set(new_selection_box, parent_pos)

  let style = match parent_team {
    Team::Enemy => {
      @sprite.DrawStyle::stroke("red", 2.0) //敌人红色描边
    }
    Team::Player => {
      @sprite.DrawStyle::stroke("lime", 2.0) //玩家绿色描边
    }
  }
  let selection_box_graphic = @sprite.ColoredShape::new(
    @sprite.Shape::rect(box_size[X], box_size[Y],0),
    style,
  )
  
  let box_sprite_visible = @sprite.Sprite::from_shape(
    selection_box_graphic, 
    200, 
    offset=@math.Vec2D(box_size[X] / -2.0, box_size[Y] / -2.0),
    layer=@sprite.RenderLayer::ui(),
  )
  let box_sprite_invisible = { ..box_sprite_visible, visible: false }
  @sprite.sprites.set(new_selection_box, box_sprite_invisible)
  
  // 返回创建好的选择框实体
  return new_selection_box
}
/// 更新所有选择框的显示状态和位置
fn update_selection_boxes_system(_backend: &@system.Backend) -> Unit {
  unit_to_selection_box.each(fn(unit, box_entity) {
    let is_selected = game_state.selected_entities.contains(unit)
    
    if @sprite.sprites.get(box_entity) is Some(sprite) {
      let new_sprite = { ..sprite, visible: is_selected }
      @sprite.sprites.set(box_entity, new_sprite)
      
      if is_selected {
        if @position.positions.get(unit) is Some(unit_pos) {
          
          @position.positions.set(box_entity, unit_pos.0.add(@math.Vec2D(0.0, 0.0)))
        }
      }
    }
  })
}


///----------------
///血条
///----------------

struct Health {
  current: Double
  max: Double
  bar_bg_entity: @system.Entity
  bar_fg_entity: @system.Entity
}
let healths: Map[@system.Entity, Health] = Map::new()
const HEALTH_BAR_WIDTH: Double = 50.0
const HEALTH_BAR_HEIGHT: Double = 5.0
const HEALTH_BAR_Y_OFFSET: Double = 3.0

//为单位附加血条
fn attach_health_bar() -> (@system.Entity, @system.Entity) {
  let bar_bg = @system.Entity::new()
  let bar_fg = @system.Entity::new()

  let bg_color_rect = @sprite.ColorRect::new(@math.Vec2D(HEALTH_BAR_WIDTH, HEALTH_BAR_HEIGHT), "red")
  let fg_color_rect = @sprite.ColorRect::new(@math.Vec2D(HEALTH_BAR_WIDTH, HEALTH_BAR_HEIGHT), "lime")

  let bg_sprite = @sprite.Sprite::from_color_rect(
    bg_color_rect, 110, layer=@sprite.RenderLayer::ui())
  let fg_sprite = @sprite.Sprite::from_color_rect(
    fg_color_rect, 111, layer=@sprite.RenderLayer::ui())
    
  @sprite.sprites.set(bar_bg, bg_sprite)
  @sprite.sprites.set(bar_fg, fg_sprite)
  
  // 只返回创建好的实体
  return (bar_bg, bar_fg)
}

fn update_health_bars_system(_backend: &@system.Backend) -> Unit {
  for unit in healths.keys() {
    if @position.positions.get(unit) is Some(unit_pos) && 
       @sprite.sprites.get(unit) is Some(unit_sprite){
      if healths.get(unit) is Some(health) {
        // 更新血条位置
        let (unit_width, unit_height) = match unit_sprite.sprite_type {
        Picture(pic) => (pic.size[X], pic.size[Y])
        Animation(anim, ..) => (anim.frames[0].size[X], anim.frames[0].size[Y])
        ColorRect(rect) => (rect.size[X], rect.size[Y])
        _ => (64.0, 64.0) // 提供一个默认尺寸
      }

        let bar_width = unit_width * 1.0
        let bar_pos_x = unit_pos.0[X] - bar_width / 2.0
        let bar_pos_y = unit_pos.0[Y] - (unit_height / 2.0) - HEALTH_BAR_Y_OFFSET
        let bar_pos = @math.Vec2D(bar_pos_x, bar_pos_y)
        @position.positions.set(health.bar_bg_entity, bar_pos)
        @position.positions.set(health.bar_fg_entity, bar_pos)

        //更新前景条宽度
        let health_percentage = health.current / health.max
        if @sprite.sprites.get(health.bar_fg_entity) is Some(fg_sprite) {
          match fg_sprite.sprite_type {
            ColorRect(rect) => {
              //创建一个具有新尺寸的 ColorRect
              let new_rect_size = @math.Vec2D(bar_width * health_percentage, HEALTH_BAR_HEIGHT)
              let new_rect = { ..rect, size: new_rect_size }
              
              //继承 zindex 和 offset
              let new_fg_sprite = @sprite.Sprite::from_color_rect(
                new_rect, 
                fg_sprite.zindex, 
                offset=fg_sprite.offset,
                layer=fg_sprite.layer,
                )
              
              @sprite.sprites.set(health.bar_fg_entity, new_fg_sprite)
            }
            //匹配类型
            _ => ()
          }
        }
      if @sprite.sprites.get(health.bar_bg_entity) is Some(bg_sprite) {
         match bg_sprite.sprite_type {
          ColorRect(rect) => {
            let new_size = @math.Vec2D(bar_width, HEALTH_BAR_HEIGHT)
            let new_rect = { ..rect, size: new_size }
            let new_sprite = @sprite.Sprite::from_color_rect(new_rect, bg_sprite.zindex, offset=bg_sprite.offset, layer=bg_sprite.layer)
            @sprite.sprites.set(health.bar_bg_entity, new_sprite)
          }
          _ => ()
        }
        }
      }
    }
  }
}

// ---------------------------------
//  附加朝向指示器 (新函数)
// ---------------------------------



let unit_to_orientation_indicator: Map[@system.Entity, @system.Entity] = Map::new()
fn attach_orientation_indicator(
  parent_unit: @system.Entity, 
  parent_pos: @math.Vec2D,
  parent_dims: @math.Vec2D,
) -> @system.Entity {
  let indicator_entity = @system.Entity::new()

  @position.positions.set(indicator_entity, parent_pos)

  let indicator_width = 4.0
  let indicator_height = parent_dims[Y]// 长度是单位高度的一半

  let indicator_graphic = @sprite.ColoredShape::new(
    @sprite.Shape::rect(indicator_width, indicator_height, 90.0),
    @sprite.DrawStyle::fill("cyan"),
  )

  let indicator_sprite = @sprite.Sprite::from_shape(
    indicator_graphic, 
    150, 
    offset=@math.Vec2D(indicator_width / -2.0, -indicator_height), 
    layer=@sprite.RenderLayer::ui(),
  )
  @sprite.sprites.set(indicator_entity, indicator_sprite)

  return indicator_entity
}
fn update_orientation_indicators_system(_backend: &@system.Backend) -> Unit {
  // 遍历所有拥有指示器的单位
  unit_to_orientation_indicator.each(fn(unit, indicator_entity) {
    // 1. 安全地获取单位和指示器都需要的所有组件
    if @position.positions.get(unit) is Some(unit_pos) &&
       @sprite.sprites.get(unit) is Some(unit_sprite) &&
       @sprite.sprites.get(indicator_entity) is Some(indicator_sprite) {

      @position.positions.set(indicator_entity, unit_pos.0)
      indicator_sprite.transform = unit_sprite.transform
    }
  })
}