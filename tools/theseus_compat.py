"""Build-only compatibility patches; pinned Vendor distributions stay byte-identical."""
from pathlib import Path


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise ValueError('Theseus compatibility patch no longer matches: ' + old[:100])
    return text.replace(old, new, 1)


def switch_source(text):
    text = replace_once(text, 'import QuartzCore', 'import QuartzCore\nimport os.log')
    text = replace_once(text, '    private var glassRevealed = false', '''    private var glassRevealed = false
    private var presentationGeneration = 0
    private static let compatibilityLog = OSLog(subsystem: "com.ning.glassswitchdock", category: "switch-frame")''')
    start = text.index('    private var theseusSourceView: UIView? {')
    end = text.index('    private func convertToTheseusContainer(', start)
    text = text[:start] + '''    // Capture the actual local hierarchy, including presented controllers. A
    // sibling glass stays in the same window/scene and inherits clipping/alpha.
    private var theseusSourceView: UIView? { superview?.superview }
    private var theseusContainer: UIView? { superview?.superview }

''' + text[end:]
    text = replace_once(text, '            glassRevealed = prefersReducedMotion', '            glassRevealed = false\n            presentationGeneration += 1\n            let generation = presentationGeneration')
    text = replace_once(text, '''                self?.revealGlass()''', '''                guard let self = self, self.presentationGeneration == generation,
                      self.window != nil, self.theseusView === glass else { return }
                self.revealGlass()''')
    # Avoid a retain cycle: the callback held by glass must not capture glass.
    text = replace_once(text, 'glass.onPresent = { [weak self] in', 'glass.onPresent = { [weak self, weak glass] in')
    text = replace_once(text, '''            revealGlass()
        }
        let lens''', '''            // No completed GPU frame: never replace a working thumb with an
            // empty CAMetalLayer. Ignore late callbacks from this attempt.
            presentationGeneration += 1
            landGlass()
            glassMorph.settle()
            stopGlassLink()
            os_log("first-frame timeout; thumb retained", log: Self.compatibilityLog, type: .error)
            return
        }
        let lens''')
    text = replace_once(text, 'thumbLayer.opacity = Float(max(fill, Self.unrevealedKnobOpacity))', 'thumbLayer.opacity = 1 // Keep the white thumb until a successful frame.')
    text = replace_once(text, '''    private func teardownGlass() {
        stopGlassLink()''', '''    private func teardownGlass() {
        presentationGeneration += 1
        theseusView?.onPresent = nil
        isPressing = false
        releaseGeneration += 1
        stopGlassLink()''')
    text = replace_once(text, '''    public override func didMoveToWindow() {''', '''    public override func didMoveToSuperview() {
        super.didMoveToSuperview()
        teardownGlass()
    }

    public override var isHidden: Bool {
        didSet { if isHidden { teardownGlass() } }
    }

    public override var isEnabled: Bool {
        didSet { if !isEnabled { teardownGlass() } }
    }

    deinit {
        theseusView?.pauseRendering()
        theseusView?.removeFromSuperview()
        glassShadowView?.removeFromSuperview()
        glassLink?.invalidate()
        trackColorLink?.invalidate()
    }

    public override func didMoveToWindow() {''')
    return text


def renderer_source(text):
    return replace_once(text, '''            commandBuffer.addCompletedHandler { _ in
                DispatchQueue.main.async(execute: onPresent)''', '''            commandBuffer.addCompletedHandler { completed in
                guard completed.status == .completed else { return }
                DispatchQueue.main.async(execute: onPresent)''')


def prepare_sources(sources, directory):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    patches = {'TheseusSwitch.swift': switch_source, 'TheseusRenderer.swift': renderer_source}
    result = []
    for source in sources:
        source = Path(source)
        if source.name in patches:
            output = directory / source.name
            output.write_text(patches[source.name](source.read_text()))
            result.append(output)
        else:
            result.append(source)
    return result
