/// ------------------------
/// 游戏实体相关定义
/// ------------------------

//创建实体示例
fn add_new_tank(pos: @math.Vec2D, team: Team) -> Unit {
  //在这里定义单位
  let unit_dimensions = @math.Vec2D(64.0, 64.0)

  //创建单位核心
  let new_tank = @system.Entity::new()
  @position.positions.set(new_tank, pos)
  @velocity.velocities.set(new_tank, @math.Vec2D(0.0, 0.0))
  
  //外观设置
  let tank_picture = @sprite.Picture::new(
    unit_dimensions,
     "assets/tank.png"
  )
  let tank_sprite = @sprite.Sprite::from_picture(
    tank_picture, 
    100, 
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
    attack_range: 65.0,
    attack_damage: 10.0,
    attack_cooldown: 0.5,
    current_cooldown: 0.0,
    aggro_range: 300.0,
  })

  // 6. 设置阵营
  teams.set(new_tank, team)
}
