import QtQuick
import QtQuick3D
import QtQuick3D.Particles3D

// A 3D particle cloud on the FOXY page (Pages/PaPage.qml) — real depth via QtQuick3D's
// Particles3D module, not a flat 2D approximation. See HISTORY.md for why: the user
// wanted something like a Three.js audio-reactive particle demo, which can't run
// directly here (this app is Qt Quick/QML, not a browser — embedding a real web engine
// already confirmed to crash this shell hard, see Pages/HomeAssistantPage.qml's own
// header comment), so this is a from-scratch equivalent built on Qt's own 3D module
// instead. Needs the `qt6-quick3d` system package (not a default Quickshell/Omarchy
// dependency) — confirmed installed before writing this file.
//
// Deliberately built from Qt's built-in "#Sphere" primitive mesh via ModelParticle3D,
// not SpriteParticle3D — a sprite particle needs a texture image, and this project has
// no image assets anywhere (every existing visual is a Nerd Font glyph, a flat color,
// or plain shapes); reusing a built-in primitive keeps that true here too. Flat-shaded
// (PrincipledMaterial.NoLighting) rather than lit, matching the rest of this app's
// flat/no-gradient design language (see omarchy-conventions.md) rather than introducing
// a rendering style nothing else on the panel uses.
//
// Reactivity is asymmetric on purpose (see HISTORY.md's brainstorm): `audioLevel` is
// Foxy's own reply volume, precomputed from the actual reply audio one file-read ahead
// of playback (daemon/src/paBridge.js's speak()) and streamed here in time with it —
// real reactivity, because we generate that audio ourselves and can measure it exactly.
// The user's own voice while `status === "listening"` gets a generic ambient pulse
// instead, deliberately not a real mic tap: the panel's mic is already a carefully
// single-consumer-at-a-time resource between Voxtype and the wake-word listener
// (HISTORY.md's whole Phase C debugging saga), and a third live consumer during a
// recording risked reintroducing that exact flakiness for a decorative effect.
Item {
    id: root
    required property var theme
    // 0..1, normalized — real reply-audio reactivity, see this file's own header.
    property real audioLevel: 0
    // "idle" | "listening" | "transcribing" | "thinking" | "speaking" (PaState.status
    // values pass straight through) — selects which motion preset applies.
    property string status: "idle"

    // A smooth, generic "breathing" pulse while listening — explicitly NOT a reaction
    // to the user's real voice (see header comment), just enough motion to read as
    // "something is happening" without pretending to measure sound we aren't tapping.
    property real _listeningPulse: 0
    SequentialAnimation on _listeningPulse {
        running: root.status === "listening"
        loops: Animation.Infinite
        NumberAnimation { from: 0.15; to: 0.55; duration: 900; easing.type: Easing.InOutSine }
        NumberAnimation { from: 0.55; to: 0.15; duration: 900; easing.type: Easing.InOutSine }
    }

    readonly property real _rawLevel: root.status === "speaking" ? root.audioLevel
        : (root.status === "listening" ? root._listeningPulse : 0)
    // A plain binding to _rawLevel, with a Behavior animating every change it receives
    // — the standard QML "smoothed proxy" idiom. Needed because paBridge.js streams
    // audioLevel at 30fps; without smoothing, the particles would snap between each
    // step instead of reading as fluid pulsing.
    property real _level: root._rawLevel
    Behavior on _level { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }

    View3D {
        id: view3d
        anchors.fill: parent

        environment: SceneEnvironment {
            backgroundMode: SceneEnvironment.Transparent
            antialiasingMode: SceneEnvironment.MSAA
            antialiasingQuality: SceneEnvironment.Medium
        }

        PerspectiveCamera {
            id: camera
            position: Qt.vector3d(0, 0, 500)
            clipFar: 2000
        }

        ParticleSystem3D {
            id: psystem
            running: true

            ParticleEmitter3D {
                id: emitter
                system: psystem
                particle: modelParticle
                // Louder/busier moments emit more, bigger, faster-scattering particles
                // — this is the actual "reacts to sound" effect the whole feature is
                // for. All three respond to the same _level so they read as one
                // coordinated pulse rather than independent, uncoordinated wobbles.
                emitRate: 22 + root._level * 55
                lifeSpan: 5000
                lifeSpanVariation: 1500
                particleScale: 0.75 + root._level * 1.1
                particleScaleVariation: 0.5
                shape: ParticleShape3D {
                    type: ParticleShape3D.Sphere
                    fill: true
                    extents: Qt.vector3d(140, 140, 140)
                }
                velocity: VectorDirection3D {
                    direction: Qt.vector3d(0, 0, 0)
                    directionVariation: Qt.vector3d(8 + root._level * 55, 8 + root._level * 55, 8 + root._level * 55)
                }
            }

            ModelParticle3D {
                id: modelParticle
                delegate: Component {
                    Model {
                        source: "#Sphere"
                        scale: Qt.vector3d(0.028, 0.028, 0.028)
                        materials: PrincipledMaterial {
                            baseColor: root.theme.foreground
                            lighting: PrincipledMaterial.NoLighting
                        }
                    }
                }
            }

            // Organic drift, present at all times (a frozen field looks broken even at
            // rest) but amplified by _level so the cloud visibly agitates when Foxy is
            // speaking loudly, not just the emitter feeding it hotter. Both a slow
            // shared sway (globalAmount) and a faster per-particle jitter (uniqueAmount)
            // so it doesn't read as one rigid block moving in lockstep.
            Wander3D {
                particles: [modelParticle]
                uniqueAmount: Qt.vector3d(18, 18, 18).times(1 + root._level * 1.5)
                uniquePace: Qt.vector3d(0.15, 0.15, 0.15)
                globalAmount: Qt.vector3d(24, 24, 24).times(1 + root._level * 2.0)
                globalPace: Qt.vector3d(0.08, 0.08, 0.08).times(1 + root._level * 1.5)
            }
        }
    }
}
