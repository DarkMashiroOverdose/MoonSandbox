// ---------------------------------
//  全新的“小火车”连接辅助函数
// ---------------------------------
/// 将一个新单位连接到玩家的“小火车”上（如果它是玩家阵营）
fn _connect_player_unit_to_train(new_unit: @system.Entity, team: Team) -> Unit {
  // 1. 将单位添加到全局单位列表中
  all_units.val.push(new_unit)

  // 2. 检查单位阵营
  if team == Team::Player {
    // a. 为这个单位创建“轨迹历史”组件，让它能被其他车厢跟随
    path_histories.set(new_unit, { points: [] })

    // b. 将这个单位连接到小火车的双向链表上
    if player_head.val is None {
      // 如果还没有火车头，这个单位就成为火车头
      player_head.val = Some(new_unit)
      player_tail.val = Some(new_unit)
      train_cars.set(new_unit, { prev: None, next: None })
    } else {
      // 如果已经有火车了，就将这个单位作为新车厢连接到车尾
      let current_tail_entity = player_tail.val.unwrap()
      if train_cars.get(current_tail_entity) is Some(tail_car_comp) {
        let updated_comp = { ..tail_car_comp, next: Some(new_unit) }
        train_cars.set(current_tail_entity, updated_comp)
      }
      train_cars.set(new_unit, { prev: Some(current_tail_entity), next: None })
      player_tail.val = Some(new_unit)
    }
  }
}


// ---------------------------------
//  重构后的单位创建函数
// ---------------------------------

fn add_new_ball(pos: @math.Vec2D, team: Team) -> Unit {
  let unit_dimensions = @math.Vec2D(32.0, 32.0)
  let new_ball = @system.Entity::new()
  @position.positions.set(new_ball, pos)
  movement_stats.set(new_ball, { speed: 3.0 })
  let ball_shape = @sprite.ColoredShape::new(@sprite.Shape::circle(16), @sprite.DrawStyle::fill("pink"))
  let ball_sprite = @sprite.Sprite::from_shape(ball_shape, 100, layer=@sprite.RenderLayer::game_world())
  @sprite.sprites.set(new_ball, ball_sprite)

  let selection_box = attach_selection_box(new_ball, pos, unit_dimensions, team)
  unit_to_selection_box.set(new_ball, selection_box)
  let (bar_bg, bar_fg) = attach_health_bar()
  
  healths.set(new_ball, { current: 100.0, max: 100.0, bar_bg_entity: bar_bg, bar_fg_entity: bar_fg })
  combat_stats.set(new_ball, { attack_range: 165.0, attack_damage: 10.0, attack_cooldown: 1.0, current_cooldown: 0.0, aggro_range: 300.0, attack_type: AttackType::Bullet, aoe_radius: 10.0 })
  teams.set(new_ball, team)

  // 【核心】调用助手函数，完成后续所有设置
  _connect_player_unit_to_train(new_ball, team)
}

fn add_new_block(pos: @math.Vec2D, team: Team) -> Unit {
  let unit_dimensions = @math.Vec2D(25.0, 25.0)
  let new_block = @system.Entity::new()
  @position.positions.set(new_block, pos)
  movement_stats.set(new_block, { speed: 3.0 })
  let block_shape = @sprite.ColoredShape::new(@sprite.Shape::rect(25,25,0), @sprite.DrawStyle::fill("yellow"))
  let block_sprite = @sprite.Sprite::from_shape(block_shape, 100, offset=@math.Vec2D(25 / -2.0, 25 / -2.0), layer=@sprite.RenderLayer::game_world())
  @sprite.sprites.set(new_block, block_sprite)

  let selection_box = attach_selection_box(new_block, pos, unit_dimensions, team)
  unit_to_selection_box.set(new_block, selection_box)
  let (bar_bg, bar_fg) = attach_health_bar()
  
  healths.set(new_block, { current: 100.0, max: 100.0, bar_bg_entity: bar_bg, bar_fg_entity: bar_fg })
  combat_stats.set(new_block, { attack_range: 165.0, attack_damage: 10.0, attack_cooldown: 2.5, current_cooldown: 0.0, aggro_range: 300.0, attack_type: AttackType::Bullet, aoe_radius: 10.0 })
  teams.set(new_block, team)

  dynamic_transforms.set(new_block, {
      rotation_speed: 2.0,
      scale_speed: 3.0,
      scale_amplitude: 0.25,
      _current_angle: 0.0,
      _time_elapsed: 0.0,
  })
  _connect_player_unit_to_train(new_block, team)
}

fn add_new_ellipse_x(pos: @math.Vec2D, team: Team) -> Unit {
  let unit_dimensions = @math.Vec2D(20.0, 20.0)
  let new_ellipse = @system.Entity::new()
  @position.positions.set(new_ellipse, pos)
  movement_stats.set(new_ellipse, { speed: 3.0 })
  let ellipse_shape = @sprite.ColoredShape::new(@sprite.Shape::ellipse(20,16,5), @sprite.DrawStyle::fill("#9E2E16"))
  let ellipse_sprite = @sprite.Sprite::from_shape(ellipse_shape, 100, layer=@sprite.RenderLayer::game_world())
  @sprite.sprites.set(new_ellipse, ellipse_sprite)

  let selection_box = attach_selection_box(new_ellipse, pos, unit_dimensions, team)
  unit_to_selection_box.set(new_ellipse, selection_box)
  let (bar_bg, bar_fg) = attach_health_bar()
  
  healths.set(new_ellipse, { current: 500.0, max: 500.0, bar_bg_entity: bar_bg, bar_fg_entity: bar_fg })
  combat_stats.set(new_ellipse, { attack_range: 165.0, attack_damage: 10.0, attack_cooldown: 3.0, current_cooldown: 0.0, aggro_range: 300.0, attack_type: AttackType::Bullet, aoe_radius: 10.0 })
  teams.set(new_ellipse, team)
  dynamic_transforms.set(new_ellipse, {
      rotation_speed: 2.0,
      scale_speed: 3.0,
      scale_amplitude: 0.25,
      _current_angle: 0.0,
      _time_elapsed: 0.0,
  })
  _connect_player_unit_to_train(new_ellipse, team)
}

fn add_new_triangle(pos: @math.Vec2D, team: Team) -> Unit {
  let unit_dimensions = @math.Vec2D(20.0, 20.0)
  let new_triangle = @system.Entity::new()
  @position.positions.set(new_triangle, pos)
  movement_stats.set(new_triangle, { speed: 3.0 })
  let triangle_shape = @sprite.ColoredShape::new(@sprite.Shape::triangle(40,0), @sprite.DrawStyle::fill("#e92cf3ff"))
  let triangle_sprite = @sprite.Sprite::from_shape(triangle_shape, 100, layer=@sprite.RenderLayer::game_world())
  @sprite.sprites.set(new_triangle, triangle_sprite)

  let selection_box = attach_selection_box(new_triangle, pos, unit_dimensions, team)
  unit_to_selection_box.set(new_triangle, selection_box)
  let (bar_bg, bar_fg) = attach_health_bar()
  
  healths.set(new_triangle, { current: 500.0, max: 500.0, bar_bg_entity: bar_bg, bar_fg_entity: bar_fg })
  combat_stats.set(new_triangle, { attack_range: 165.0, attack_damage: 10.0, attack_cooldown: 3.0, current_cooldown: 0.0, aggro_range: 300.0, attack_type: AttackType::Bullet, aoe_radius: 10.0 })
  teams.set(new_triangle, team)

  _connect_player_unit_to_train(new_triangle, team)
}
fn add_rolling_triangle(pos: @math.Vec2D, team: Team) -> Unit {
  let unit_dimensions = @math.Vec2D(40.0, 40.0) 
  let new_triangle = @system.Entity::new()
  @position.positions.set(new_triangle, pos)
  movement_stats.set(new_triangle, { speed: 3.0 })

  let triangle_shape_geom = @sprite.Shape::triangle(40.0, 0.0)

  let triangle_colored_shape = @sprite.ColoredShape::new(
    triangle_shape_geom, 
    @sprite.DrawStyle::fill("#86ff05ff")
  )

  let triangle_sprite = @sprite.Sprite::from_shape(
    triangle_colored_shape, 
    100, 
    offset = @math.Vec2D(-20.0, -20.0),
    layer=@sprite.RenderLayer::game_world()
  )
  @sprite.sprites.set(new_triangle, triangle_sprite)

  let selection_box = attach_selection_box(new_triangle, pos, unit_dimensions, team)
  unit_to_selection_box.set(new_triangle, selection_box)
  let (bar_bg, bar_fg) = attach_health_bar()
  
  healths.set(new_triangle, { current: 500.0, max: 500.0, bar_bg_entity: bar_bg, bar_fg_entity: bar_fg })
  combat_stats.set(new_triangle, { attack_range: 165.0, attack_damage: 10.0, attack_cooldown: 3.0, current_cooldown: 0.0, aggro_range: 300.0, attack_type: AttackType::Bullet, aoe_radius: 10.0 })
  teams.set(new_triangle, team)
  
  dynamic_transforms.set(new_triangle, {
    rotation_speed: 2.0,
    scale_speed: 3.0,
    scale_amplitude: 0.25,
    _current_angle: 0.0,
    _time_elapsed: 0.0,
  })
  _connect_player_unit_to_train(new_triangle, team)
}

fn add_new_tank(pos: @math.Vec2D, team: Team) -> Unit {
  let unit_dimensions = @math.Vec2D(64.0, 64.0)
  let new_tank = @system.Entity::new()
  @position.positions.set(new_tank, pos)
  movement_stats.set(new_tank, { speed: 1.0 })
  let tank_picture = @sprite.Picture::new(unit_dimensions, "assets/tank.png")
  let tank_sprite = @sprite.Sprite::from_picture(tank_picture, 100, offset=@math.Vec2D(64 / -2.0, 64 / -2.0), layer=@sprite.RenderLayer::game_world())
  @sprite.sprites.set(new_tank, tank_sprite)

  let selection_box = attach_selection_box(new_tank, pos, unit_dimensions, team)
  unit_to_selection_box.set(new_tank, selection_box)
  let (bar_bg, bar_fg) = attach_health_bar()
  
  healths.set(new_tank, { current: 100.0, max: 100.0, bar_bg_entity: bar_bg, bar_fg_entity: bar_fg })
  combat_stats.set(new_tank, { attack_range: 165.0, attack_damage: 10.0, attack_cooldown: 1.5, current_cooldown: 0.0, aggro_range: 300.0, attack_type: AttackType::Bullet, aoe_radius: 10.0 })
  teams.set(new_tank, team)
  
  _connect_player_unit_to_train(new_tank, team)
}

fn add_new_soldier(pos: @math.Vec2D, team: Team) -> Unit {
  let unit_dimensions = @math.Vec2D(35.0, 67.0)
  let new_soldier = @system.Entity::new()
  @position.positions.set(new_soldier, pos)
  movement_stats.set(new_soldier, { speed: 2.0 })
  let soldier_picture = @sprite.Picture::new(unit_dimensions, "assets/soldier.png")
  let soldier_sprite = @sprite.Sprite::from_picture(soldier_picture, 100, offset=@math.Vec2D(35 / -2.0, 67 / -2.0), layer=@sprite.RenderLayer::game_world())
  @sprite.sprites.set(new_soldier, soldier_sprite)

  let selection_box = attach_selection_box(new_soldier, pos, unit_dimensions, team)
  unit_to_selection_box.set(new_soldier, selection_box)
  let (bar_bg, bar_fg) = attach_health_bar()
  
  healths.set(new_soldier, { current: 100.0, max: 100.0, bar_bg_entity: bar_bg, bar_fg_entity: bar_fg })
  combat_stats.set(new_soldier, { attack_range: 65.0, attack_damage: 10.0, attack_cooldown: 0.5, current_cooldown: 0.0, aggro_range: 300.0, attack_type: AttackType::Melee, aoe_radius: 0.0 })
  teams.set(new_soldier, team)

  _connect_player_unit_to_train(new_soldier, team)
}