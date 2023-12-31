import std/random, std/strformat, std/logging, std/math
import sdl2, sdl2/image

const
    WindowWidth            = 1422
    WindowHeight           = 800
    ParticlesCap           = 1024
    FireworksCap           = 32
    Friction               = 0.98
    Gravity                = 0.1
    FPS                    = 60
    ParticleWidth          = 20
    ParticleHeight         = 20
    FireworkParticlesCount = 50
    TrailLength            = 20
    ParticleVelocityMin    = 2
    ParticleVelocityMax    = 7
    ParticleLifetime       = 130
    FireworkSpeed          = 10
    FireworkLifetimeMin    = 45
    FireworkLifetimeMax    = 60
    CannonDelay            = 15
    CannonSpeed            = 10
    DelayBarWidth          = WindowWidth / 4

let colors = @[
    sdl2.color(r = 255, g = 255, b = 255, a = SDL_ALPHA_OPAQUE),
    sdl2.color(r = 255, g = 100, b = 100, a = SDL_ALPHA_OPAQUE),
    sdl2.color(r = 100, g = 255, b = 100, a = SDL_ALPHA_OPAQUE),
    sdl2.color(r = 100, g = 100, b = 255, a = SDL_ALPHA_OPAQUE),
    sdl2.color(r = 100, g = 255, b = 255, a = SDL_ALPHA_OPAQUE),
    sdl2.color(r = 255, g = 255, b = 100, a = SDL_ALPHA_OPAQUE),
    sdl2.color(r = 255, g = 100, b = 255, a = SDL_ALPHA_OPAQUE),
    sdl2.color(r = 255, g = 200, b = 200, a = SDL_ALPHA_OPAQUE),
    sdl2.color(r = 200, g = 255, b = 200, a = SDL_ALPHA_OPAQUE),
    sdl2.color(r = 200, g = 200, b = 255, a = SDL_ALPHA_OPAQUE),
    sdl2.color(r = 200, g = 255, b = 255, a = SDL_ALPHA_OPAQUE),
    sdl2.color(r = 255, g = 255, b = 200, a = SDL_ALPHA_OPAQUE),
    sdl2.color(r = 255, g = 200, b = 255, a = SDL_ALPHA_OPAQUE),
]

proc randomColor(): (uint8, uint8, uint8) =
    let color = colors[int(rand(float(colors.len)))]
    (color.r, color.g, color.b)

var logger = newConsoleLogger()

type SDLException = object of Defect

template sdlFailIf(condition: typed, reason: string) =
    if condition:
        logger.log(lvlFatal, reason & ": " & $sdl2.getError())
        quit(QuitFailure)

type Trail = object
    x, y, rotation: float
    enabled: bool

type Particle = object
    x, y, vx, vy: float

    rotation: float
    r, g, b: uint8

    now, time: int

    trail: array[TrailLength, Trail]

proc randRange(min, max: float): float =
    rand(float(max - min)) + float(min)

proc createParticle(x, y: float, r, g, b: uint8): Particle =
    var particle = Particle(
        x: x, y: y,
        r: r, g: g, b: b,
        time: ParticleLifetime,
        now:  ParticleLifetime
    )
    let
        velocity = randRange(ParticleVelocityMin, ParticleVelocityMax)
        angle    = rand(360.0)

    particle.vx = cos(angle * (PI / 180)) * velocity
    particle.vy = sin(angle * (PI / 180)) * velocity - Gravity * 10

    particle

proc update(self: var Particle) =
    if self.now <= 0:
        return

    dec self.now

    self.x  += self.vx
    self.y  += self.vy
    self.vx *= Friction
    self.vy *= Friction
    self.vy += Gravity

    self.rotation += float(self.now / 10)

    if self.now mod 2 == 0:
        self.trail[0].x        = self.x
        self.trail[0].y        = self.y
        self.trail[0].rotation = self.rotation
        self.trail[0].enabled  = true

        for i in countdown(TrailLength - 1, 1):
            self.trail[i] = self.trail[i - 1]

type Firework = object
    x, y: float
    r, g, b: uint8
    now, time: int

proc createFirework(x, y: float): Firework =
    let
        (r, g, b) = randomColor()
        lifetime  = int(randRange(FireworkLifetimeMin, FireworkLifetimeMax))
    Firework(
        x: x, y: y,
        r: r, g: g, b: b,
        time: lifetime,
        now:  lifetime,
    )

proc update(self: var Firework) =
    if self.now <= 0:
        return

    dec self.now

    self.y -= FireworkSpeed

type State = object
    quit: bool

    win: sdl2.WindowPtr
    ren: sdl2.RendererPtr

    sparkle: sdl2.TexturePtr

    particles: array[ParticlesCap, Particle]
    fireworks: array[FireworksCap, Firework]

    cannonX, cannonDelay: int
    cannonAuto: bool

proc loadImage(self: var State, path: string): TexturePtr =
    let surface = image.load(path)
    sdlFailIf surface == nil: &"Failed to load image \"{path}\""

    let texture = sdl2.createTextureFromSurface(self.ren, surface)
    sdlFailIf texture == nil: &"Failed to load image \"{path}\""

    texture

proc addParticle(self: var State, newParticle: Particle) =
    for particle in self.particles.mitems:
        if particle.now == 0:
            particle = newParticle
            break

proc addFirework(self: var State, newFirework: Firework) =
    for firework in self.fireworks.mitems:
        if firework.now == 0:
            firework = newFirework
            break

proc renderSparkle(self: var State, x, y: float, r, g, b, a: uint8, rotation: float) =
        var rect = sdl2.rect(
            x = cint(x),             y = cint(y),
            w = cint(ParticleWidth), h = cint(ParticleHeight),
        )

        self.sparkle.setTextureAlphaMod(a)
        discard self.sparkle.setTextureColorMod(r, g, b)
        self.ren.copyEx(self.sparkle, nil, addr rect, rotation, nil, SDL_FLIP_NONE)

proc particleExplosion(self: var State, x, y: float, r, g, b: uint8) =
    for i in 1 .. FireworkParticlesCount:
        self.addParticle(createParticle(
            x = x, y = y,
            r = r, g = g, b = b,
        ))

proc render(self: var State) =
    self.ren.setDrawColor(5, 5, 22, SDL_ALPHA_OPAQUE)
    self.ren.clear()

    for firework in self.fireworks.mitems:
        if firework.now == 0:
            continue

        self.renderSparkle(
            x = firework.x, y = firework.y,
            r = firework.r, g = firework.g, b = firework.b, a = SDL_ALPHA_OPAQUE,
            rotation = firework.y,
        )

        firework.update()
        if firework.now == 0:
            self.particleExplosion(
                x = firework.x, y = firework.y,
                r = firework.r, g = firework.g, b = firework.b,
            )

    for particle in self.particles.mitems:
        if particle.now == 0:
            continue

        self.renderSparkle(
            x = particle.x, y = particle.y,
            r = particle.r, g = particle.g, b = particle.b,
            a = uint8(particle.now / particle.time * 255),
            rotation = particle.rotation,
        )

        for i in countdown(TrailLength - 1, 1):
            let trail = particle.trail[i]
            if not trail.enabled:
                continue

            self.renderSparkle(
                x = trail.x, y = trail.y,
                r = particle.r, g = particle.g, b = particle.b,
                a = uint8((1.0 - i / TrailLength) * 80 * (particle.now / particle.time)),
                rotation = trail.rotation,
            )

        particle.update()

    if not self.cannonAuto:
        self.renderSparkle(
            x = float(self.cannonX), y = WindowHeight - ParticleHeight,
            r = 255, g = 255, b = 255, a = SDL_ALPHA_OPAQUE,
            rotation = 0,
        )

        let
            n = self.cannonDelay / CannonDelay
            w = cint((1 - n) * DelayBarWidth)

        var rect = sdl2.rect(
            x = cint(WindowWidth / 2 - w / 2),
            y = 20,
            w = w,
            h = cint(5),
        )
        self.ren.setDrawColor(uint8(n * 255), uint8((1 - n) * 255), 0, SDL_ALPHA_OPAQUE)
        self.ren.fillRect(addr rect)

    self.ren.present()

proc fireCannon(self: var State) =
    if self.cannonDelay == 0:
        self.addFirework(createFirework(float(self.cannonX), WindowHeight))
        self.cannonDelay = CannonDelay

proc input(self: var State) =
    if self.cannonDelay > 0:
        dec self.cannonDelay

    if self.cannonAuto:
        self.cannonX = rand(WindowWidth)
        self.fireCannon()

    var evt = defaultEvent
    while sdl2.pollEvent(evt):
        case evt.kind:
            of QuitEvent:
                self.quit = true

            of KeyDown:
                case evt.key.keysym.scancode:
                    of SDL_SCANCODE_ESCAPE:
                        self.quit = true

                    of SDL_SCANCODE_RETURN:
                        self.cannonAuto = not self.cannonAuto

                    else: discard

            else: discard

    let keyboard = sdl2.getKeyboardState()

    if not self.cannonAuto:
        if keyboard[int(SDL_SCANCODE_RIGHT)] == 1:
            self.cannonX += CannonSpeed
            if self.cannonX >= WindowWidth:
                self.cannonX = WindowWidth - 1

        if keyboard[int(SDL_SCANCODE_LEFT)] == 1:
            self.cannonX -= CannonSpeed
            if self.cannonX < 0:
                self.cannonX = 0

        if keyboard[int(SDL_SCANCODE_SPACE)] == 1:
            self.fireCannon()

proc mainLoop(self: var State) =
    while not self.quit:
        self.render()
        self.input()

        sdl2.delay(uint32(FPS / 1000))

proc start(self: var State) =
    sdlFailIf not sdl2.init(INIT_VIDEO): "Failed to initialize SDL"
    defer: sdl2.quit()

    sdlFailIf image.init(IMG_INIT_PNG) < 0: "Failed to initialize SDL_image"
    defer: image.quit()

    self.win = sdl2.createWindow(
        title = "Nimworks!",
        x = SDL_WINDOWPOS_CENTERED, y = SDL_WINDOWPOS_CENTERED,
        w = WindowWidth,            h = WindowHeight,
        flags = SDL_WINDOW_RESIZABLE
    )
    sdlFailIf self.win.isNil: "Failed to create window"
    defer: self.win.destroy()

    self.ren = sdl2.createRenderer(
        window = self.win,
        index  = -1,
        flags  = Renderer_Accelerated or Renderer_PresentVsync or Renderer_TargetTexture
    )
    sdlFailIf self.ren.isNil: "Failed to create renderer"
    defer: self.ren.destroy()

    sdlFailIf self.ren.setLogicalSize(WindowWidth, WindowHeight) != 0: "Failed to set logical size"

    self.sparkle = self.loadImage("./res/sparkle.png")

    echo """

  °  ☆⋰ • █ █ █▀█ █▀█ █▀█ █ █ ★ ⋱ *” •
    ★”  ⋱ █▀█ █▀█ █▀▀ █▀▀ ▀█▀ ⋰ ☆  °
       *  ▀ ▀ ▀ ▀ ▀   ▀    ▀   •
    █▄ █ █▀▀ █ █ █  █ █ █▀▀ █▀█ █▀█
    █ ██ █▀▀ █ █ █  ▀█▀ █▀▀ █▀█ ██▀
    ▀  ▀ ▀▀▀  ▀▀▀    ▀  ▀▀▀ ▀ ▀ ▀ ▀
"""

    self.cannonAuto = true
    self.mainLoop()

when isMainModule:
    var state: State
    start(state)
