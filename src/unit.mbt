/// ------------------------
/// 游戏实体相关定义
/// ------------------------
fn add_new_ball(pos: @math.Vec2D, team: Team) -> Unit {
  //在这里定义单位
  let unit_dimensions = @math.Vec2D(32.0, 32.0)

  //创建单位核心
  let new_ball = @system.Entity::new()
  @position.positions.set(new_ball, pos)
  
  movement_stats.set(new_ball, { speed: 3.0 }) 
  //外观设置

  let ball_shape = @sprite.ColoredShape::new(
    @sprite.Shape::circle(16),
    @sprite.DrawStyle::fill("pink"),
  )
  
  let ball_sprite = @sprite.Sprite::from_shape(
    ball_shape, 
    100, 
    layer=@sprite.RenderLayer::game_world()
  )
  @sprite.sprites.set(new_ball, ball_sprite)
  all_units.val.push(new_ball)

  //避障实体大小
  avoidance_behaviors.set(new_ball, {
    unit_radius: unit_dimensions[X] / 1.5, //默认比实体本身小一点，但是可以调整
    avoidance_radius: 60.0, // 寻敌半径
  })

  //附加选择框和血条
  let selection_box = attach_selection_box(new_ball, pos, unit_dimensions, team)
  unit_to_selection_box.set(new_ball, selection_box)
  let (bar_bg, bar_fg) = attach_health_bar()
  
  // 5. 设置生命值和战斗数值 (这部分不变)
  healths.set(new_ball, { 
    current: 100.0, 
    max: 100.0,
    bar_bg_entity: bar_bg,
    bar_fg_entity: bar_fg,
  })
  combat_stats.set(new_ball, {
    attack_range: 165.0,
    attack_damage: 10.0,
    attack_cooldown: 1,
    current_cooldown: 0.0,
    aggro_range: 300.0,
    attack_type: AttackType::Bullet, // 攻击类型设为子弹
    aoe_radius: 10,        // 不是AoE单位，半径为0
  })
  // 6. 设置阵营
  teams.set(new_ball, team)

  all_units.val.push(new_ball)
}

fn add_new_block(pos: @math.Vec2D, team: Team) -> Unit {
  //在这里定义单位
  let unit_dimensions = @math.Vec2D(25.0, 25.0)

  //创建单位核心
  let new_block = @system.Entity::new()
  @position.positions.set(new_block, pos)
  
  movement_stats.set(new_block, { speed: 3.0 }) 
  //外观设置

  let block_shape = @sprite.ColoredShape::new(
    @sprite.Shape::rect(25,25),
    @sprite.DrawStyle::fill("yellow"),
  )
  
  let block_sprite = @sprite.Sprite::from_shape(
    block_shape, 
    100, 
    offset=@math.Vec2D(25 / -2.0, 25 / -2.0),
    layer=@sprite.RenderLayer::game_world()
  )
  @sprite.sprites.set(new_block, block_sprite)
  all_units.val.push(new_block)

  //避障实体大小
  avoidance_behaviors.set(new_block, {
    unit_radius: unit_dimensions[X] / 1.5, //默认比实体本身小一点，但是可以调整
    avoidance_radius: 60.0, // 寻敌半径
  })

  //附加选择框和血条
  let selection_box = attach_selection_box(new_block, pos, unit_dimensions, team)
  unit_to_selection_box.set(new_block, selection_box)
  let (bar_bg, bar_fg) = attach_health_bar()
  
  // 5. 设置生命值和战斗数值 (这部分不变)
  healths.set(new_block, { 
    current: 100.0, 
    max: 100.0,
    bar_bg_entity: bar_bg,
    bar_fg_entity: bar_fg,
  })
  combat_stats.set(new_block, {
    attack_range: 165.0,
    attack_damage: 10.0,
    attack_cooldown: 2.5,
    current_cooldown: 0.0,
    aggro_range: 300.0,
    attack_type: AttackType::Bullet, // 攻击类型设为子弹
    aoe_radius: 10,        // 不是AoE单位，半径为0
  })
  // 6. 设置阵营
  teams.set(new_block, team)

  all_units.val.push(new_block)
}


fn add_new_ellipse_x(pos: @math.Vec2D, team: Team) -> Unit {
  //在这里定义单位
  let unit_dimensions = @math.Vec2D(20.0, 20.0)

  //创建单位核心
  let new_ellipse = @system.Entity::new()
  @position.positions.set(new_ellipse, pos)
  
  movement_stats.set(new_ellipse, { speed: 3.0 }) 
  //外观设置

  let ellipse_shape = @sprite.ColoredShape::new(
    @sprite.Shape::ellipse(20,16,5),
    @sprite.DrawStyle::fill("#9E2E16"),
  )
  
  let ellipse_sprite = @sprite.Sprite::from_shape(
    ellipse_shape, 
    100, 
    layer=@sprite.RenderLayer::game_world()
  )
  @sprite.sprites.set(new_ellipse, ellipse_sprite)
  all_units.val.push(new_ellipse)

  //避障实体大小
  avoidance_behaviors.set(new_ellipse, {
    unit_radius: unit_dimensions[X] / 1.5, //默认比实体本身小一点，但是可以调整
    avoidance_radius: 60.0, // 寻敌半径
  })

  //附加选择框和血条
  let selection_box = attach_selection_box(new_ellipse, pos, unit_dimensions, team)
  unit_to_selection_box.set(new_ellipse, selection_box)
  let (bar_bg, bar_fg) = attach_health_bar()
  
  // 5. 设置生命值和战斗数值 (这部分不变)
  healths.set(new_ellipse, { 
    current: 500.0, 
    max: 500.0,
    bar_bg_entity: bar_bg,
    bar_fg_entity: bar_fg,
  })
  combat_stats.set(new_ellipse, {
    attack_range: 165.0,
    attack_damage: 10.0,
    attack_cooldown: 3,
    current_cooldown: 0.0,
    aggro_range: 300.0,
    attack_type: AttackType::Bullet, // 攻击类型设为子弹
    aoe_radius: 10,        // 不是AoE单位，半径为0
  })
  // 6. 设置阵营
  teams.set(new_ellipse, team)

  all_units.val.push(new_ellipse)
}

//创建实体示例
fn add_new_tank(pos: @math.Vec2D, team: Team) -> Unit {
  //在这里定义单位
  let unit_dimensions = @math.Vec2D(64.0, 64.0)

  //创建单位核心
  let new_tank = @system.Entity::new()
  @position.positions.set(new_tank, pos)
  
  movement_stats.set(new_tank, { speed: 1.0 }) 
  
  //外观设置
  let tank_picture = @sprite.Picture::new(
    unit_dimensions,
     "assets/tank.png"
  )
  //let tank_picture = @sprite.ColoredShape::new(
  //  @sprite.Shape::rect(64,64),
  //  @sprite.DrawStyle::stroke("red", 2.0),
  //)
  
  let tank_sprite = @sprite.Sprite::from_picture(
    tank_picture, 
    100, 
    offset=@math.Vec2D(64 / -2.0, 64 / -2.0),
    layer=@sprite.RenderLayer::game_world()
  )
  @sprite.sprites.set(new_tank, tank_sprite)
  all_units.val.push(new_tank)

  //避障实体大小
  avoidance_behaviors.set(new_tank, {
    unit_radius: unit_dimensions[X] / 1.5, //默认比实体本身小一点，但是可以调整
    avoidance_radius: 60.0, // 寻敌半径
  })

  //附加选择框和血条
  let selection_box = attach_selection_box(new_tank, pos, unit_dimensions, team)
  unit_to_selection_box.set(new_tank, selection_box)
  let (bar_bg, bar_fg) = attach_health_bar()
  
  // 5. 设置生命值和战斗数值 (这部分不变)
  healths.set(new_tank, { 
    current: 100.0, 
    max: 100.0,
    bar_bg_entity: bar_bg,
    bar_fg_entity: bar_fg,
  })
  combat_stats.set(new_tank, {
    attack_range: 165.0,
    attack_damage: 10.0,
    attack_cooldown: 1.5,
    current_cooldown: 0.0,
    aggro_range: 300.0,
    attack_type: AttackType::Bullet, // 攻击类型设为子弹
    aoe_radius: 10,        // 不是AoE单位，半径为0
  })
  // 6. 设置阵营
  teams.set(new_tank, team)
}

//创建实体示例
fn add_new_soldier(pos: @math.Vec2D, team: Team) -> Unit {
  //在这里定义单位
  let unit_dimensions = @math.Vec2D(35.0, 67.0)

  //创建单位核心
  let new_soldier = @system.Entity::new()
  @position.positions.set(new_soldier, pos)
  
  movement_stats.set(new_soldier, { speed: 2.0 }) 
  
  //外观设置
  let soldier_picture = @sprite.Picture::new(
    unit_dimensions,
     "assets/soldier.png"
  )
  let soldier_sprite = @sprite.Sprite::from_picture(
    soldier_picture, 
    100, 
    offset=@math.Vec2D(35 / -2.0, 67 / -2.0),
    layer=@sprite.RenderLayer::game_world()
  )
  @sprite.sprites.set(new_soldier, soldier_sprite)
  all_units.val.push(new_soldier)

  //避障实体大小
  avoidance_behaviors.set(new_soldier, {
    unit_radius: unit_dimensions[X] / 1.5, //默认比实体本身小一点，但是可以调整
    avoidance_radius: 60.0, // 寻敌半径
  })

  //附加选择框和血条
  let selection_box = attach_selection_box(new_soldier, pos, unit_dimensions, team)
  unit_to_selection_box.set(new_soldier, selection_box)
  let (bar_bg, bar_fg) = attach_health_bar()
  
  // 5. 设置生命值和战斗数值 (这部分不变)
  healths.set(new_soldier, { 
    current: 100.0, 
    max: 100.0,
    bar_bg_entity: bar_bg,
    bar_fg_entity: bar_fg,
  })
  combat_stats.set(new_soldier, {
    attack_range: 65.0,
    attack_damage: 10.0,
    attack_cooldown: 0.5,
    current_cooldown: 0.0,
    aggro_range: 300.0,
    attack_type: AttackType::Melee, // 攻击类型设为近战
    aoe_radius: 0.0,        // 不是AoE单位，半径为0
  })
  // 6. 设置阵营
  teams.set(new_soldier, team)
}
