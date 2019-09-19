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
            .background(Color.green.opacity(0.2))
    }
}

final class ViewAttachmentCell: NSTextAttachmentCell {
    let content: AttachmentType
    let attachedView: NSView
    let viewController: NSViewController

    init(content: AttachmentType) {
        let viewController = content.createViewController()
        self.viewController = viewController
        self.attachedView = viewController.view
        self.content = content
        super.init()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect, glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        return NSRect(x: position.x, y: position.y, width: self.attachedView.fittingSize.width, height: self.attachedView.fittingSize.height)
    }
}

final class ViewAttachmentLayoutManager: NSLayoutManager {
    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        self.textStorage?.enumerateAttribute(.attachment, in: glyphsToShow, options: [.longestEffectiveRangeNotRequired]) { value, range, stop in
            guard let attachment = value as? NSTextAttachment else { return }
            if let attachmentCell = attachment.attachmentCell as? ViewAttachmentCell {
                guard let textContainer = self.textContainer(forGlyphAt: range.location, effectiveRange: nil) else {
                    print("WAH OH TEXT CONTAINER")
                    return
                }
                var boundingRect = self.boundingRect(forGlyphRange: range, in: textContainer)
                attachmentCell.attachedView.frame = boundingRect
                attachmentCell.attachedView.isHidden = false
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
        let filename = "\(uuid).fluencyattachment"
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

//final class ViewAttachment: NSTextAttachment {
//    let attachedView: NSView
//    private let viewController: NSViewController
//
//    init(content: AttachmentType) {
//        print("Initializing ViewAttachment from content")
//        self.viewController = content.createViewController()
//        self.attachedView = self.viewController.view
//        let fileWrapper = content.asFileWrapper()
//        super.init(data: fileWrapper.regularFileContents!, ofType: "com.noahgilmore.fluencytextdata")
////        super.init(fileWrapper: fileWrapper)
//        self.fileWrapper = fileWrapper
//        self.attachmentCell = ViewAttachmentCell(content: content)
//    }
//
//    override init(data contentData: Data?, ofType uti: String?) {
//        print("Initializing ViewAttachment from data")
//        guard let data = contentData, let uti = uti else { fatalError() }
//        let decoder = JSONDecoder()
//        let content = try! decoder.decode(AttachmentType.self, from: data)
//        self.viewController = content.createViewController()
//        self.attachedView = self.viewController.view
//        super.init(data: contentData, ofType: uti)
//        self.attachmentCell = ViewAttachmentCell(content: content)
//    }
//
//    deinit {
//        self.attachedView.removeFromSuperview()
//    }
//
//    required init?(coder: NSCoder) {
//        fatalError("init(coder:) has not been implemented")
//    }
//}

final class AttachmentTypeWrapper: NSObject, NSPasteboardWriting {
    let attachmentType: AttachmentType

    init(attachmentType: AttachmentType) {
        self.attachmentType = attachmentType
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        return [.string]
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        let encoder = JSONEncoder()
        return try! encoder.encode(attachmentType)
    }
}

final class TextViewDelegate: NSObject, NSTextViewDelegate {
    func textView(_ view: NSTextView, writablePasteboardTypesFor cell: NSTextAttachmentCellProtocol, at charIndex: Int) -> [NSPasteboard.PasteboardType] {
        return [.fileContents]
    }

    func textView(_ view: NSTextView, write cell: NSTextAttachmentCellProtocol, at charIndex: Int, to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if let cell = cell as? ViewAttachmentCell, type == .fileContents {
            print("Writing cell content as file wrapper...")
            let result = pboard.write(cell.content.asFileWrapper())
            print("Writing result: \(result)")
            return true
        }
        return true
    }

    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        print("Should change? \(affectedCharRange)")
        if (replacementString ?? "").count == 0 {
            // We're deleting text, make sure to delete attachments too
            print("Deleting in affected range: \(affectedCharRange)")
            textView.textStorage?.enumerateAttribute(.attachment, in: affectedCharRange, options: []) { value, range, stop in
                if let attachment = value as? NSTextAttachment,
                    let cell = attachment.attachmentCell as? ViewAttachmentCell {
                    print("Deleting attachment at range: \(range)")
                    cell.attachedView.removeFromSuperview()
                }
            }
            textView.textStorage?.removeAttribute(.attachment, range: affectedCharRange)
        }
        return true
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
        self.isRichText = true
        self.textContainer!.replaceLayoutManager(self.attachmentLayoutManager)

        self.textStorage?.append(NSAttributedString(string: "Hello world", attributes: [NSAttributedString.Key.foregroundColor: NSColor.labelColor]))

        let content: AttachmentType = .square(number: 5)
        let attachment = NSTextAttachment(fileWrapper: content.asFileWrapper())
        attachment.attachmentCell = ViewAttachmentCell(content: content)
        let string = NSAttributedString(attachment: attachment)
        self.textStorage?.append(string)
        self.typingAttributes = [.foregroundColor: NSColor.labelColor]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        return [.fileContents] + super.readablePasteboardTypes
    }

    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
        return [.fileContents] + super.writablePasteboardTypes
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        let constant = (self.typingAttributes[.font] as? NSFont)?.pointSize ?? NSFont.systemFontSize
        super.drawInsertionPoint(in: NSRect(x: rect.origin.x, y: rect.origin.y + (rect.size.height - constant), width: rect.size.width, height: constant), color: color, turnedOn: flag)
    }

    override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if type == .fileContents {
            do {
                let fileWrapper = try self.textStorage!.fileWrapper(from: self.selectedRange(), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
                let uuid = UUID()
                fileWrapper.preferredFilename = "\(uuid).fluencytextstorage"
                pboard.write(fileWrapper)
                return true
            } catch let error {
                print("Error: \(error)")
                return false
            }
        }
        return super.writeSelection(to: pboard, type: type)
    }

    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        print("Reading selection of type \(type) from pasteboard...")
        if type == NSPasteboard.PasteboardType.fileContents {
            let wrapper = pboard.readFileWrapper()!
            guard let attributedString = NSAttributedString(rtfdFileWrapper: wrapper, documentAttributes: nil) else {
                print("Error!! Could not create attributed string")
                return false
            }
            self.textStorage?.insert(attributedString, at: self.selectedRange().location)
            return true
        }
        return super.readSelection(from: pboard, type: type)
    }
}

extension CustomTextView: NSTextStorageDelegate {
    func textStorage(_ textStorage: NSTextStorage, willProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        textStorage.enumerateAttribute(.attachment, in: NSMakeRange(0, textStorage.length), options: .longestEffectiveRangeNotRequired) { value, range, stop in
            if let attachment = value as? NSTextAttachment {
                if !(attachment.attachmentCell is ViewAttachmentCell),
                    let wrapper = attachment.fileWrapper,
                    let preferredFilename = wrapper.preferredFilename,
                    preferredFilename.contains(".fluencyattachment") {
                    let decoder = JSONDecoder()
                    let content = try! decoder.decode(AttachmentType.self, from: wrapper.regularFileContents!)
                    let attachmentCell = ViewAttachmentCell(content: content)
                    attachment.attachmentCell = attachmentCell
                    print("Adding subview from willProcessEditing with deserialization")
                    self.addSubview(attachmentCell.attachedView)
                } else if let cell = attachment.attachmentCell as? ViewAttachmentCell {
                    if cell.attachedView.superview == nil {
                        print(textStorage)
                        print("Adding subview from willProcessEditing with ViewAttachmentCell")
                        self.addSubview(cell.attachedView)
                    }
                }
            }
        }
    }
}
