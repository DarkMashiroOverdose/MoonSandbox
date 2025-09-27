pub enum EnemyType {
  Grunt       // 杂兵
  TankEnemy   // 中坚
  Archer      // 射手
  Bomber      // 炸弹兵
} derive(Show, Eq, @json.FromJson)

pub fn spawn_enemy(enemy_type: EnemyType, pos: @math.Vec2D) -> Unit {
  match enemy_type {
    EnemyType::Grunt => add_new_grunt(pos)
    EnemyType::TankEnemy => add_new_tank_enemy(pos)
    EnemyType::Archer => add_new_archer(pos)
    EnemyType::Bomber => add_new_bomber(pos)
  }
}

fn add_new_grunt(pos: @math.Vec2D) -> Unit {
  let unit_dimensions = @math.Vec2D(20.0, 30.0) // 胶囊的尺寸
  let new_unit = @system.Entity::new()
  @position.positions.set(new_unit, pos)
  movement_stats.set(new_unit, { speed: 1.5 })
  sizes.set(new_unit, { radius: 12.0 })

  // 用 rect 来模拟胶囊形状
  let shape = @sprite.ColoredShape::new(@sprite.Shape::rect(20.0, 30.0, 10.0), @sprite.DrawStyle::fill("#FF7A5A"))
  let sprite = @sprite.Sprite::from_shape(shape, 100, offset=@math.Vec2D(-10.0, -15.0))
  @sprite.sprites.set(new_unit, sprite)

  let (bar_bg, bar_fg) = attach_health_bar()
  healths.set(new_unit, { current: 50.0, max: 50.0, bar_bg_entity: bar_bg, bar_fg_entity: bar_fg })
  teams.set(new_unit, Team::Enemy)

  combat_stats.set(
  new_unit, { 
    attack_range: 40.0,
    on_hit_effects: [OnHitEffect::DealDamage(8.0, None)], 
    attack_cooldown: 1.0, 
    current_cooldown: 0.0, 
    aggro_range: 500.0,
    attack_type: AttackType::Melee,
    aoe_radius: 0.0,
    crit_rate: 0.0,
    on_hit_vfx: VFX_Type::MeleeSlash,
    area_effect_vfx: None,
  })
  all_units.val.push(new_unit)
}
fn add_new_tank_enemy(pos: @math.Vec2D) -> Unit {
  let unit_dimensions = @math.Vec2D(50.0, 50.0)
  let new_unit = @system.Entity::new()
  @position.positions.set(new_unit, pos)
  movement_stats.set(new_unit, { speed: 0.8 })
  sizes.set(new_unit, { radius: 25.0 })

  let shape = @sprite.ColoredShape::new(@sprite.Shape::circle(25.0), @sprite.DrawStyle::fill("#D92A2A"))
  let sprite = @sprite.Sprite::from_shape(shape, 100)
  @sprite.sprites.set(new_unit, sprite)

  let (bar_bg, bar_fg) = attach_health_bar()
  healths.set(new_unit, { current: 300.0, max: 300.0, bar_bg_entity: bar_bg, bar_fg_entity: bar_fg })
  teams.set(new_unit, Team::Enemy)

  combat_stats.set(new_unit, { 
    attack_range: 50.0,
    on_hit_effects: [OnHitEffect::DealDamage(12.0, Some(VFX_Type::MeleeSlash))],
    attack_cooldown: 2.5,
    current_cooldown: 0.0, 
    aggro_range: 500.0,
    attack_type: AttackType::AoE,
    aoe_radius: 60.0,
    crit_rate: 0.05,
    on_hit_vfx: VFX_Type::MeleeSlash,
    area_effect_vfx: None,
  })
  all_units.val.push(new_unit)
}

fn add_new_archer(pos: @math.Vec2D) -> Unit {
  let unit_dimensions = @math.Vec2D(30.0, 30.0)
  let new_unit = @system.Entity::new()
  @position.positions.set(new_unit, pos)
  movement_stats.set(new_unit, { speed: 1.2 })
  sizes.set(new_unit, { radius: 15.0 })

  let shape = @sprite.ColoredShape::new(@sprite.Shape::triangle(30.0, 0.0), @sprite.DrawStyle::fill("#FF9900"))
  let sprite = @sprite.Sprite::from_shape(shape, 100, offset=@math.Vec2D(-15.0, -15.0))
  @sprite.sprites.set(new_unit, sprite)

  let (bar_bg, bar_fg) = attach_health_bar()
  healths.set(new_unit, { current: 60.0, max: 60.0, bar_bg_entity: bar_bg, bar_fg_entity: bar_fg }) 
  teams.set(new_unit, Team::Enemy)

  combat_stats.set(new_unit, { 
    attack_range: 250.0, 
    on_hit_effects: [OnHitEffect::DealDamage(15.0, None)], 
    attack_cooldown: 1.8, 
    current_cooldown: 0.0, 
    aggro_range: 500.0,
    attack_type: AttackType::Bullet,
    aoe_radius: 0.0,
    crit_rate: 0.1,
    on_hit_vfx: VFX_Type::BulletImpact, 
    area_effect_vfx: None,
  })
  all_units.val.push(new_unit)
}
fn add_new_bomber(pos: @math.Vec2D) -> Unit {
  let unit_dimensions = @math.Vec2D(40.0, 40.0)
  let new_unit = @system.Entity::new()
  @position.positions.set(new_unit, pos)
  movement_stats.set(new_unit, { speed: 1.0 })
  sizes.set(new_unit, { radius: 20.0 })

  let shape = @sprite.ColoredShape::new(@sprite.Shape::rect(30.0, 30.0, 0.0), @sprite.DrawStyle::fill("#A83232"))
  let sprite = @sprite.Sprite::from_shape(shape, 100, offset=@math.Vec2D(-15.0, -15.0))
  @sprite.sprites.set(new_unit, sprite)

  let (bar_bg, bar_fg) = attach_health_bar()
  healths.set(new_unit, { current: 80.0, max: 80.0, bar_bg_entity: bar_bg, bar_fg_entity: bar_fg })
  teams.set(new_unit, Team::Enemy)

  combat_stats.set(new_unit, { 
    attack_range: 220.0,
    on_hit_effects: [
      OnHitEffect::AreaOfEffect(
        [OnHitEffect::DealDamage(25.0, None)],
        80.0,
        Some(VFX_Type::BulletImpact), 
      )
    ],
    attack_cooldown: 3.5, // 攻速非常慢
    current_cooldown: 0.0, 
    aggro_range: 500.0,
    attack_type: AttackType::Bullet,
    aoe_radius: 0.0,
    crit_rate: 0.05,
    on_hit_vfx: VFX_Type::BulletImpact, // 子弹本身的命中特效
    area_effect_vfx: None, // 因为区域效果本身很短，所以不需要持续特效
  })
  all_units.val.push(new_unit)
}