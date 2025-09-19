let one_shot_effects: Set[@system.Entity] = Set::new()

// 【修正】去掉了 frame_count=
let explosion_frames: Array[@sprite.AnimationFrame] = @sprite.frames_from_atlas(
  "assets/explosion150xA.png",
  8, // <-- 直接传递数字 5
  width=184.5,
  height=150.0,
)

// Create a non-looping explosion animation
let explosion_animation: @sprite.Animation = @sprite.Animation::new(explosion_frames, loop_=false, rate=0.5)
fn cleanup_effects_system(_backend: &@system.Backend) -> Unit {
  for effect in one_shot_effects.to_array() {
    // 使用 Selene 提供的函数检查动画是否播放完毕
    if @sprite.is_animation_finished(effect) {
      // 如果播放完了，就把它加入到我们已有的垃圾回收列表
      entities_to_cleanup.val.push(effect)
      // 别忘了从特效列表中移除，避免重复检查
      one_shot_effects.remove(effect)
    }
  }
}