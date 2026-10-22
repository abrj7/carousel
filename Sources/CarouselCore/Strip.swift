import CoreGraphics

public typealias WindowID = UInt32

/// When the strip scrolls to bring the focused column into view.
public enum CentreMode: String, CaseIterable, Sendable {
    /// Scroll the minimum amount needed (PaperWM style).
    case never
    /// Left-align while everything fits, otherwise centre the focused column.
    case onOverflow
    /// Always keep the focused column in the middle of the screen.
    case always
}

/// One column of the strip. Usually holds a single window; stacks hold several.
public struct Column: Equatable, Sendable {
    public private(set) var windows: [WindowID]
    /// Relative height of each window in a stack. Same count as `windows`.
    public private(set) var weights: [Double]
    public internal(set) var focusedRow: Int = 0
    /// Fraction of the usable viewport width (0...1].
    public internal(set) var width: Double
    var widthBeforeFull: Double?

    public init(_ window: WindowID, width: Double) {
        windows = [window]
        weights = [1]
        self.width = width
    }

    public var focusedWindow: WindowID { windows[min(focusedRow, windows.count - 1)] }

    mutating func append(_ id: WindowID) {
        windows.append(id)
        weights.append(1)
    }

    mutating func remove(at row: Int) {
        windows.remove(at: row)
        weights.remove(at: row)
        if row < focusedRow || focusedRow >= windows.count { focusedRow = max(0, focusedRow - 1) }
    }

    mutating func swapRows(_ a: Int, _ b: Int) {
        windows.swapAt(a, b)
        weights.swapAt(a, b)
    }

    mutating func setWeight(_ w: Double, at row: Int) { weights[row] = w }
    mutating func equalize() { weights = Array(repeating: 1, count: windows.count) }
}

/// Which way a window was pushed off screen.
public enum ParkSide: Equatable, Sendable { case none, left, right }

/// An infinite horizontal strip of columns viewed through a screen-sized viewport.
///
/// Coordinates: "strip space" starts at 0 on the strip's left edge. `offset` is the strip-space
/// x of the viewport's left edge. All frames returned are in the same space as the viewport rect
/// passed in (the app uses Accessibility coordinates: origin top-left of the main display).
public struct Strip: Equatable, Sendable {
    public private(set) var columns: [Column] = []
    public private(set) var focusedColumn = 0
    public var offset: Double = 0

    public init() {}

    public var isEmpty: Bool { columns.isEmpty }
    public var focusedWindow: WindowID? { columns.isEmpty ? nil : columns[focusedColumn].focusedWindow }
    public var windows: [WindowID] { columns.flatMap(\.windows) }

    public func locate(_ id: WindowID) -> (column: Int, row: Int)? {
        for (c, col) in columns.enumerated() {
            if let r = col.windows.firstIndex(of: id) { return (c, r) }
        }
        return nil
    }

    public func contains(_ id: WindowID) -> Bool { locate(id) != nil }

    // MARK: Membership

    /// Inserts a window as a new column. Defaults to just right of the focused column.
    /// Focus stays on whatever column was focused before.
    public mutating func insert(_ id: WindowID, width: Double, at index: Int? = nil) {
        guard !contains(id) else { return }
        let idx = clamp(index ?? (columns.isEmpty ? 0 : focusedColumn + 1), 0, columns.count)
        columns.insert(Column(id, width: clamp(width, 0.05, 1)), at: idx)
        if columns.count > 1 && idx <= focusedColumn { focusedColumn += 1 }
    }

    @discardableResult
    public mutating func remove(_ id: WindowID) -> Bool {
        guard let (c, r) = locate(id) else { return false }
        columns[c].remove(at: r)
        if columns[c].windows.isEmpty {
            columns.remove(at: c)
            if c < focusedColumn || focusedColumn >= columns.count { focusedColumn = max(0, focusedColumn - 1) }
        }
        return true
    }

    // MARK: Focus

    @discardableResult
    public mutating func focus(_ id: WindowID) -> Bool {
        guard let (c, r) = locate(id) else { return false }
        focusedColumn = c
        columns[c].focusedRow = r
        return true
    }

    public mutating func focusColumn(_ index: Int) {
        guard !isEmpty else { return }
        focusedColumn = clamp(index, 0, columns.count - 1)
    }

    public mutating func focusLeft() { focusColumn(focusedColumn - 1) }
    public mutating func focusRight() { focusColumn(focusedColumn + 1) }
    public mutating func focusFirst() { focusColumn(0) }
    public mutating func focusLast() { focusColumn(columns.count - 1) }

    public mutating func focusUp() {
        guard !isEmpty else { return }
        columns[focusedColumn].focusedRow = max(0, columns[focusedColumn].focusedRow - 1)
    }

    public mutating func focusDown() {
        guard !isEmpty else { return }
        let col = columns[focusedColumn]
        columns[focusedColumn].focusedRow = min(col.windows.count - 1, col.focusedRow + 1)
    }

    // MARK: Moving

    public mutating func moveLeft() {
        guard focusedColumn > 0 else { return }
        columns.swapAt(focusedColumn, focusedColumn - 1)
        focusedColumn -= 1
    }

    public mutating func moveRight() {
        guard focusedColumn < columns.count - 1 else { return }
        columns.swapAt(focusedColumn, focusedColumn + 1)
        focusedColumn += 1
    }

    public mutating func moveUp() {
        guard !isEmpty else { return }
        let r = columns[focusedColumn].focusedRow
        guard r > 0 else { return }
        columns[focusedColumn].swapRows(r, r - 1)
        columns[focusedColumn].focusedRow = r - 1
    }

    public mutating func moveDown() {
        guard !isEmpty else { return }
        let r = columns[focusedColumn].focusedRow
        guard r < columns[focusedColumn].windows.count - 1 else { return }
        columns[focusedColumn].swapRows(r, r + 1)
        columns[focusedColumn].focusedRow = r + 1
    }

    /// Moves a column from one index to another (drag to reorder in the strip indicator).
    public mutating func reorder(from: Int, to: Int) {
        guard columns.indices.contains(from), columns.indices.contains(to), from != to else { return }
        let focusedID = focusedWindow
        let col = columns.remove(at: from)
        columns.insert(col, at: to)
        if let focusedID { focus(focusedID) }
    }

    // MARK: Stacks

    /// Moves the focused window into the neighbouring column (`direction` -1 = left, +1 = right).
    public mutating func stack(direction: Int) {
        guard !isEmpty else { return }
        let source = focusedColumn
        var target = source + (direction < 0 ? -1 : 1)
        guard columns.indices.contains(target) else { return }
        let id = columns[source].focusedWindow
        columns[source].remove(at: columns[source].focusedRow)
        columns[target].append(id)
        columns[target].focusedRow = columns[target].windows.count - 1
        if columns[source].windows.isEmpty {
            columns.remove(at: source)
            if source < target { target -= 1 }
        }
        focusedColumn = target
    }

    /// Pulls the focused window out of its stack into a new column on one side.
    public mutating func popOut(direction: Int) {
        guard !isEmpty, columns[focusedColumn].windows.count > 1 else { return }
        let col = columns[focusedColumn]
        let id = col.focusedWindow
        columns[focusedColumn].remove(at: col.focusedRow)
        let idx = direction < 0 ? focusedColumn : focusedColumn + 1
        columns.insert(Column(id, width: col.width), at: idx)
        focusedColumn = idx
    }

    // MARK: Sizing

    public mutating func cycleWidth(presets: [Double]) {
        guard !isEmpty, let first = presets.min() else { return }
        let w = columns[focusedColumn].width
        columns[focusedColumn].width = presets.sorted().first { $0 > w + 0.01 } ?? first
        columns[focusedColumn].widthBeforeFull = nil
    }

    public mutating func toggleFullWidth() {
        guard !isEmpty else { return }
        var col = columns[focusedColumn]
        if col.width >= 0.999 {
            col.width = col.widthBeforeFull ?? 0.5
            col.widthBeforeFull = nil
        } else {
            col.widthBeforeFull = col.width
            col.width = 1
        }
        columns[focusedColumn] = col
    }

    public mutating func resizeWidth(by delta: Double) {
        guard !isEmpty else { return }
        columns[focusedColumn].width = clamp(columns[focusedColumn].width + delta, 0.1, 1)
        columns[focusedColumn].widthBeforeFull = nil
    }

    public mutating func setWidth(of id: WindowID, to fraction: Double) {
        guard let (c, _) = locate(id) else { return }
        columns[c].width = clamp(fraction, 0.05, 1)
    }

    public mutating func resizeHeight(by delta: Double) {
        guard !isEmpty, columns[focusedColumn].windows.count > 1 else { return }
        let col = columns[focusedColumn]
        let total = col.weights.reduce(0, +)
        let w = max(0.1 * total, col.weights[col.focusedRow] + delta * total)
        columns[focusedColumn].setWeight(w, at: col.focusedRow)
    }

    public mutating func equalizeHeights() {
        guard !isEmpty else { return }
        columns[focusedColumn].equalize()
    }

    // MARK: Geometry

    /// Pixel width of a column. Chosen so that e.g. two 0.5 columns plus three gaps fill the
    /// viewport exactly, and a 1.0 column fills it with a gap on each side.
    public static func pixelWidth(_ fraction: Double, viewportWidth vw: Double, gap: Double) -> Double {
        max(1, fraction * (vw - gap) - gap)
    }

    /// Inverse of `pixelWidth`.
    public static func fraction(forPixelWidth px: Double, viewportWidth vw: Double, gap: Double) -> Double {
        (px + gap) / max(1, vw - gap)
    }

    public func widths(viewportWidth vw: Double, gap: Double) -> [Double] {
        columns.map { Strip.pixelWidth($0.width, viewportWidth: vw, gap: gap) }
    }

    /// Strip-space x of each column's left edge.
    public func lefts(viewportWidth vw: Double, gap: Double) -> [Double] {
        var x = gap
        return widths(viewportWidth: vw, gap: gap).map { w in
            defer { x += w + gap }
            return x
        }
    }

    public func totalWidth(viewportWidth vw: Double, gap: Double) -> Double {
        widths(viewportWidth: vw, gap: gap).reduce(gap) { $0 + $1 + gap }
    }

    public func isFullyVisible(_ index: Int, viewportWidth vw: Double, gap: Double) -> Bool {
        guard columns.indices.contains(index) else { return false }
        let l = lefts(viewportWidth: vw, gap: gap)[index] - offset
        let r = l + widths(viewportWidth: vw, gap: gap)[index]
        return l >= -0.5 && r <= vw + 0.5
    }

    /// Scrolls so the focused column is on screen, according to `mode`.
    public mutating func scrollToFocused(viewportWidth vw: Double, gap: Double, mode: CentreMode) {
        guard !isEmpty else { offset = 0; return }
        let l = lefts(viewportWidth: vw, gap: gap)[focusedColumn]
        let w = widths(viewportWidth: vw, gap: gap)[focusedColumn]
        let total = totalWidth(viewportWidth: vw, gap: gap)
        switch mode {
        case .always:
            offset = l + w / 2 - vw / 2
        case .onOverflow:
            offset = total <= vw ? 0 : l + w / 2 - vw / 2
            clampOffset(viewportWidth: vw, gap: gap)
        case .never:
            guard !isFullyVisible(focusedColumn, viewportWidth: vw, gap: gap) else { return }
            if l - gap < offset || w + 2 * gap > vw {
                offset = l - gap
            } else {
                offset = l + w + gap - vw
            }
            clampOffset(viewportWidth: vw, gap: gap)
        }
    }

    /// Puts the focused column in the middle of the viewport, even at the ends of the strip.
    public mutating func centreFocused(viewportWidth vw: Double, gap: Double) {
        guard !isEmpty else { return }
        let l = lefts(viewportWidth: vw, gap: gap)[focusedColumn]
        let w = widths(viewportWidth: vw, gap: gap)[focusedColumn]
        offset = l + w / 2 - vw / 2
    }

    public mutating func clampOffset(viewportWidth vw: Double, gap: Double) {
        let total = totalWidth(viewportWidth: vw, gap: gap)
        offset = clamp(offset, 0, max(0, total - vw))
    }

    /// Settles a free scroll (trackpad) onto the nearest column edge. Focus stays put if the
    /// focused column is still fully visible, otherwise it moves to the column we snapped to.
    public mutating func snap(viewportWidth vw: Double, gap: Double, mode: CentreMode) {
        guard !isEmpty else { offset = 0; return }
        let ls = lefts(viewportWidth: vw, gap: gap)
        if mode == .always {
            let centre = offset + vw / 2
            let ws = widths(viewportWidth: vw, gap: gap)
            let nearest = ls.indices.min { abs(ls[$0] + ws[$0] / 2 - centre) < abs(ls[$1] + ws[$1] / 2 - centre) }!
            focusedColumn = nearest
            centreFocused(viewportWidth: vw, gap: gap)
            return
        }
        let nearest = ls.indices.min { abs(ls[$0] - gap - offset) < abs(ls[$1] - gap - offset) }!
        offset = ls[nearest] - gap
        clampOffset(viewportWidth: vw, gap: gap)
        if !isFullyVisible(focusedColumn, viewportWidth: vw, gap: gap) {
            focusedColumn = ls.indices.first { isFullyVisible($0, viewportWidth: vw, gap: gap) } ?? nearest
        }
    }

    /// Where every window should be, given the viewport (usable screen area) and gap size.
    /// Windows may land partly or fully outside the viewport; see `park`.
    public func frames(in viewport: CGRect, gap: Double) -> [(id: WindowID, frame: CGRect)] {
        let vw = Double(viewport.width)
        let ls = lefts(viewportWidth: vw, gap: gap)
        let ws = widths(viewportWidth: vw, gap: gap)
        var out: [(WindowID, CGRect)] = []
        for (i, col) in columns.enumerated() {
            let x = Double(viewport.minX) + ls[i] - offset
            let n = Double(col.windows.count)
            let available = Double(viewport.height) - 2 * gap - (n - 1) * gap
            let totalWeight = col.weights.reduce(0, +)
            var y = Double(viewport.minY) + gap
            for (r, id) in col.windows.enumerated() {
                let h = available * col.weights[r] / totalWeight
                out.append((id, CGRect(x: x.rounded(), y: y.rounded(), width: ws[i].rounded(), height: h.rounded())))
                y += h + gap
            }
        }
        return out
    }
}

/// macOS won't let a window sit completely off screen, so windows that scroll out of view are
/// parked against the screen edge with a `sliver` of pixels still showing.
public func park(_ frame: CGRect, in viewport: CGRect, sliver: Double = 1) -> (frame: CGRect, side: ParkSide) {
    var f = frame
    if Double(frame.maxX) <= Double(viewport.minX) + sliver {
        f.origin.x = viewport.minX - frame.width + sliver
        return (f, .left)
    }
    if Double(frame.minX) >= Double(viewport.maxX) - sliver {
        f.origin.x = viewport.maxX - sliver
        return (f, .right)
    }
    return (f, .none)
}

func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { min(max(v, lo), hi) }
