"""Guarded build-only patches; pinned Vendor files remain byte-identical."""
from pathlib import Path


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise ValueError('Theseus compatibility patch no longer matches: ' + old[:100])
    return text.replace(old, new, 1)


def switch_source(text):
    text = replace_once(text, '    private var glassRevealed = false', '''    private var glassRevealed = false
    private var presentationGeneration = 0''')
    start = text.index('    private var theseusSourceView: UIView? {')
    end = text.index('    private func convertToTheseusContainer(', start)
    text = replace_once(text, text[start:end], '''    // Keep capture and glass in the control's actual window and local hierarchy.
    private var theseusSourceView: UIView? { self }
    private var theseusContainer: UIView? { superview?.superview }

''')
    text = replace_once(text, '            glassRevealed = prefersReducedMotion', '''            glassRevealed = false
            presentationGeneration += 1
            let generation = presentationGeneration''')
    text = replace_once(text, 'glass.onPresent = { [weak self] in', 'glass.onPresent = { [weak self, weak glass] in')
    text = replace_once(text, '                self?.revealGlass()', '''                guard let self = self, self.presentationGeneration == generation,
                      self.window != nil, self.theseusView === glass else { return }
                self.revealGlass()''')
    text = replace_once(text, '''            revealGlass()
        }
        let lens''', '''            // Keep the working thumb when no successful GPU frame arrived.
            presentationGeneration += 1
            landGlass()
            glassMorph.settle()
            stopGlassLink()
            return
        }
        let lens''')
    text = replace_once(text, 'thumbLayer.opacity = Float(max(fill, Self.unrevealedKnobOpacity))', 'thumbLayer.opacity = 1 // Retain thumb until a successful first frame.')
    text = replace_once(text, '''    private func teardownGlass() {
        stopGlassLink()''', '''    private func teardownGlass() {
        presentationGeneration += 1
        theseusView?.onPresent = nil
        isPressing = false
        releaseGeneration += 1
        stopGlassLink()''')
    text = replace_once(text, '    public override func didMoveToWindow() {', '''    public override func didMoveToSuperview() {
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
    text = replace_once(text, '\n        glass.sourceView = sourceView\n', '''
        glass.sourceView = sourceView
        // Capture only this 63 x 28 control. An opaque semantic base prevents
        // transparent app containers becoming black in the refraction shader.
        // Hide the thumb in the CPU capture, never in a presented transaction.
        glass.captureWillBegin = { [weak self] in
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self?.contentView.backgroundColor = .secondarySystemGroupedBackground
            self?.thumbLayer.isHidden = true
        }
        glass.captureDidEnd = { [weak self] in
            if let self = self {
                self.contentView.backgroundColor = .clear
                self.thumbLayer.isHidden = false
            }
            CATransaction.commit()
        }
''')
    text = replace_once(text, '        if let sourceView = theseusSourceView, sourceView.bounds.width > 0 {',
                        '        if let sourceView = theseusSourceView, sourceView.bounds.width > 0, glass.sourceView !== sourceView {')
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
