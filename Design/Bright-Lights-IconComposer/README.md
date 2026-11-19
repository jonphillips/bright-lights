# Bright Lights — Icon Composer layers

Three aligned 1024 × 1024 PNG layers, plus an assembled preview.

| Stack order | File | Contents |
| --- | --- | --- |
| Back | layers/01-night-sky.png | Opaque navy sky with blue haze and amber glow |
| Middle | layers/02-skyline.png | Transparent NYC skyline with illuminated Empire State Building |
| Front | layers/03-theater-marquee.png | Transparent theater facade, marquee, six upper bulbs and three underside lights |

## Import

1. Create an iPhone/iPad/Mac icon in Icon Composer using its 1024 × 1024 canvas.
2. Import all three files from `layers/`. Arrange them in the back-to-front order above. The sidebar's frontmost layer should be the theater.
3. Keep each image at its full 1024 × 1024 canvas size, centered, with no independent cropping or fit-to-content scaling. Transparent padding registers the layers.
4. Treat the opaque sky as the lowest artwork layer. Start with Liquid Glass disabled on the painted artwork and specular effects off, then add effects sparingly while previewing. The artwork already contains modeled light and shading.
5. Let Icon Composer supply the system corner mask. The files deliberately have square canvases and no baked outer border or upper-left glass reflection.
6. Preview the default, dark and mono appearances, including a small home-screen size, then save your `.icon` document from Icon Composer.

`assembled-preview.png` is a flat check of alignment, not an import layer. This package contains PNG source layers, not a tested native `.icon` project. Icon Composer was not available in this environment for app-level verification.

## Reconstruction notes

The source was a flattened generated image. These layers were reconstructed with image editing, preserving its layout and design closely; they are not recovered original vector layers or a pixel-exact decomposition. Hidden areas were filled, the lower skyline was feathered into transparency, and the facade was extended to the canvas edges. The source's neon outer rim and glass glare were removed deliberately.

The transparent skyline and theater layers were verified to contain real alpha transparency. All three canvases are 1024 × 1024 and the assembled stack was visually checked.

Original reference: https://chatgpt.com/s/m_6aff0235b62881919a352357d7a1a5a0
Apple workflow: https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer
Apple effects discussion: https://developer.apple.com/videos/play/wwdc2025/361/
