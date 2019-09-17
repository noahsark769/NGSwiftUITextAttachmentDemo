//
//  CustomTextView.swift
//  NGSwiftUITextAttachmentDemo
//
//  Created by Noah Gilmore on 9/15/19.
//  Copyright © 2019 Noah Gilmore. All rights reserved.
//

import Foundation
import AppKit
import SwiftUI

struct RedSquareView: View, Codable {
    let number: Int

    var body: some View {
        Text("\(number)")
            .frame(width: 50, height: 50)
            .background(Color.red)
        .padding(100)
    }
}

final class ViewAttachmentCell: NSTextAttachmentCell {
    let content: AttachmentType

    init(content: AttachmentType) {
        self.content = content
        super.init()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect, glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        guard let attachment = self.attachment as? ViewAttachment else { return .zero }
        return NSRect(x: position.x, y: position.y, width: attachment.attachedView.fittingSize.width, height: attachment.attachedView.fittingSize.height)
    }
}

final class ViewAttachmentLayoutManager: NSLayoutManager {
    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        self.textStorage?.enumerateAttribute(.attachment, in: glyphsToShow, options: [.longestEffectiveRangeNotRequired]) { value, range, stop in

            if let attachment = value as? ViewAttachment {
                guard let textContainer = self.textContainer(forGlyphAt: range.location, effectiveRange: nil) else {
                    print("WAH OH TEXT CONTAINER")
                    return
                }
                var boundingRect = self.boundingRect(forGlyphRange: range, in: textContainer)
                attachment.attachedView.frame = boundingRect
                attachment.attachedView.isHidden = false
            }
        }
    }
}

enum AttachmentType {
    case square(number: Int)

    func createViewController() -> NSViewController {
        switch self {
        case let .square(number):
            return NSHostingController(rootView: RedSquareView(number: number))
        }
    }

    func asFileWrapper() -> FileWrapper {
        let encoder = JSONEncoder()
        let data = try! encoder.encode(self)
        let wrapper = FileWrapper(regularFileWithContents: data)
        let uuid = UUID()
        let filename = "\(uuid).fluencytextdata"
        wrapper.filename = filename
        wrapper.preferredFilename = filename
        return wrapper
    }
}

extension AttachmentType: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case data
    }

    enum AttachmentTypeError: Error {
        case invalidType
    }

    private enum Raw: String {
        case square
    }

    private var rawType: Raw {
        switch self {
        case .square: return.square
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let rawType = Raw(rawValue: try container.decode(String.self, forKey: .type)) else {
            throw AttachmentTypeError.invalidType
        }
        switch rawType {
        case .square:
            self = .square(number: try container.decode(Int.self, forKey: .data))
        }
    }

    func encode(to encoder: Encoder) throws {
        let raw = self.rawType
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(raw.rawValue, forKey: .type)

        switch self {
        case let .square(number):
            try container.encode(number, forKey: .data)
        }
    }
}

final class ViewAttachment: NSTextAttachment {
    let attachedView: NSView
    private let viewController: NSViewController

    init(content: AttachmentType) {
        self.viewController = content.createViewController()
        self.attachedView = self.viewController.view
        super.init(data: nil, ofType: nil)
        self.fileWrapper = content.asFileWrapper()
        self.attachmentCell = ViewAttachmentCell(content: content)
    }

    override init(data contentData: Data?, ofType uti: String?) {
        guard let data = contentData, let uti = uti else { fatalError() }
        let decoder = JSONDecoder()
        let content = try! decoder.decode(AttachmentType.self, from: data)
        self.viewController = content.createViewController()
        self.attachedView = self.viewController.view
        super.init(data: contentData, ofType: uti)
        self.attachmentCell = ViewAttachmentCell(content: content)
    }

    deinit {
        self.attachedView.removeFromSuperview()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class TextViewDelegate: NSObject, NSTextViewDelegate {
    func textView(_ view: NSTextView, writablePasteboardTypesFor cell: NSTextAttachmentCellProtocol, at charIndex: Int) -> [NSPasteboard.PasteboardType] {
        print("Calling writeablePasteboardTypes with cell \(cell)")
        return [.fileContents]
    }

    func textView(_ view: NSTextView, write cell: NSTextAttachmentCellProtocol, at charIndex: Int, to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        print("Writing some cell, not sure if gunna do it: \(cell), \(type)")
        if let cell = cell as? ViewAttachmentCell, type == .fileContents {
            print("Writing cell content as file wrapper...")
            pboard.write(cell.content.asFileWrapper())
            if let attachment = cell.attachment as? ViewAttachment {
                attachment.attachedView.removeFromSuperview()
            }
            return true
        }
        return false
    }
}

final class CustomTextView: NSTextView {
    private let attachmentLayoutManager = ViewAttachmentLayoutManager()
    private let theDelegate = TextViewDelegate()

    init() {
        let initialized = NSTextView(frame: .zero)
        super.init(frame: initialized.frame, textContainer: initialized.textContainer)

        self.isEditable = true
        self.isSelectable = true
        self.textContainerInset = .zero
        self.textColor = NSColor.labelColor
        self.delegate = self.theDelegate
        self.textStorage?.delegate = self
        self.textContainer!.replaceLayoutManager(self.attachmentLayoutManager)

        self.textStorage?.append(NSAttributedString(string: "Hello world", attributes: [NSAttributedString.Key.foregroundColor: NSColor.labelColor]))

        let string = NSAttributedString(attachment: ViewAttachment(content: .square(number: 5)))
        self.textStorage?.append(string)

        self.typingAttributes = [.foregroundColor: NSColor.labelColor]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        let constant = (self.typingAttributes[.font] as? NSFont)?.pointSize ?? NSFont.systemFontSize
        super.drawInsertionPoint(in: NSRect(x: rect.origin.x, y: rect.origin.y + (rect.size.height - constant), width: rect.size.width, height: constant), color: color, turnedOn: flag)
    }

//    override func didChangeText() {
//        super.didChangeText()
//        print("DidChangeText called!")
//        guard let storage = self.textStorage else { return }
//        storage.enumerateAttribute(.attachment, in: NSMakeRange(0, storage.length   ), options: .longestEffectiveRangeNotRequired) { value, range, stop in
//            print("Found attachment: \(value)")
//            if let attachment = value as? NSTextAttachment {
//                print("-- Found a regular NSTextAttachment")
//            }
//            guard let attachment = value as? ViewAttachment else {
//                return
//            }
//            print("-- Found a fancy ViewAttachment!")
//            self.addSubview(attachment.attachedView)
//        }
//    }
}

extension CustomTextView: NSTextStorageDelegate {
    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        print("DidProcessEditing: \(editedMask), \(editedRange), delta \(delta)")
        textStorage.enumerateAttribute(.attachment, in: NSMakeRange(0, textStorage.length), options: .longestEffectiveRangeNotRequired) { value, range, stop in
            print("Found attachment: \(value)")
            if let attachment = value as? NSTextAttachment {
                print("-- Found a regular NSTextAttachment")
            }
            guard let attachment = value as? ViewAttachment else {
                return
            }
            print("-- Found a fancy ViewAttachment!")
            if attachment.attachedView.superview == nil {
                self.addSubview(attachment.attachedView)
            }
        }

//        let length = textStorage.length
//        var effectiveRange = NSMakeRange(0, 0)
//        while NSMaxRange(effectiveRange) < length {
//            print("Checking \(NSMaxRange(effectiveRange))")
//            if let attachment = textStorage.attribute(.attachment, at: NSMaxRange(effectiveRange), effectiveRange: &effectiveRange) {
//                print("Found attachment: \(attachment)")
//            }
//        }
    }
}
