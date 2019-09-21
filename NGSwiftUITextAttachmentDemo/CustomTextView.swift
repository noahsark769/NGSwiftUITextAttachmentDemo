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
import Combine

struct RedSquareView: View, AttachmentTypeProducer {
    @State var number: Int = 0
    @State var text: String = ""

    var body: some View {
        VStack {
            Text("\(number)")
            Button(action: {
                self.number += 1
                self.didUpdateAttachmentType.send(.square(data: IntAndText(number: self.number, text: self.text)))
            }, label: {
                Text("Increment")
            })
            TextField("Field", text: self.$text, onEditingChanged: { _ in }, onCommit: {
                self.didUpdateAttachmentType.send(.square(data: IntAndText(number: self.number, text: self.text)))
            })
        }.frame(width: 150)
            .background(Color.red)
        .padding(100)
            .background(Color.green.opacity(0.2))
    }

    let didUpdateAttachmentType = PassthroughSubject<AttachmentType, Never>()
}

final class ViewAttachmentCell: NSTextAttachmentCell {
    var content: AttachmentType
    let attachedView: NSView
    let viewController: NSViewController
    private var cancellables = Set<AnyCancellable>()

    init(content: AttachmentType) {
        let viewController = content.createViewController()
        self.viewController = viewController
        self.attachedView = viewController.view
        self.content = content
        super.init()

        viewController.didUpdateAttachmentType.sink(receiveValue: { newAttachmentType in
            self.content = newAttachmentType
            self.attachment?.fileWrapper = self.content.asFileWrapper()
        }).store(in: &self.cancellables)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func cellSize() -> NSSize {
        return self.attachedView.fittingSize
    }

    override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect, glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        let rect = NSRect(x: position.x, y: position.y, width: self.attachedView.fittingSize.width, height: self.attachedView.fittingSize.height - position.y) // why do we have to minus the position here??
        return rect
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
                let size = attachmentCell.attachedView.fittingSize
                attachmentCell.attachedView.frame =  boundingRect
                attachmentCell.attachedView.isHidden = false
            }
        }
    }
}

protocol AttachmentTypeProducer {
    var didUpdateAttachmentType: PassthroughSubject<AttachmentType, Never> { get }
}

extension NSHostingController: AttachmentTypeProducer where Content: AttachmentTypeProducer {
    var didUpdateAttachmentType: PassthroughSubject<AttachmentType, Never> {
        return self.rootView.didUpdateAttachmentType
    }
}

struct IntAndText: Codable {
    let number: Int
    let text: String
}

enum AttachmentType {
    case square(data: IntAndText)

    func createViewController() -> NSViewController & AttachmentTypeProducer {
        switch self {
        case let .square(data):
            return NSHostingController(rootView: RedSquareView(number: data.number, text: data.text))
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
            self = .square(data: try container.decode(IntAndText.self, forKey: .data))
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

final class TextViewDelegate: NSObject, NSTextViewDelegate {
    func textView(_ view: NSTextView, writablePasteboardTypesFor cell: NSTextAttachmentCellProtocol, at charIndex: Int) -> [NSPasteboard.PasteboardType] {
        return [.fileContents]
    }

    func textView(_ view: NSTextView, write cell: NSTextAttachmentCellProtocol, at charIndex: Int, to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if let cell = cell as? ViewAttachmentCell, type == .fileContents {
            let result = pboard.write(cell.content.asFileWrapper())
            return result
        }
        return true
    }

    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        if affectedCharRange.length > 0 && replacementString != nil {
            // We're deleting text, make sure to delete attachments too
            textView.textStorage?.enumerateAttribute(.attachment, in: affectedCharRange, options: []) { value, range, stop in
                if let attachment = value as? NSTextAttachment,
                    let cell = attachment.attachmentCell as? ViewAttachmentCell {
                    cell.attachedView.removeFromSuperview()
                }
            }
            textView.textStorage?.removeAttribute(.attachment, range: affectedCharRange)
            textView.typingAttributes[.attachment] = nil
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
        self.textContainer!.replaceLayoutManager(self.attachmentLayoutManager)

        self.textStorage?.append(NSAttributedString(string: "Hello world", attributes: [NSAttributedString.Key.foregroundColor: NSColor.labelColor]))

        let content: AttachmentType = .square(data: IntAndText(number: 5, text: "Nested Text Field"))
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
                return super.writeSelection(to: pboard, type: type) // or true?
            } catch let error {
                print("Error: \(error)")
                return super.writeSelection(to: pboard, type: type)
            }
        }
        return super.writeSelection(to: pboard, type: type)
    }

    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        print("Reading selection of type \(type) from pasteboard...")
        if type == NSPasteboard.PasteboardType.fileContents {
            let wrapper = pboard.readFileWrapper()!
            if wrapper.isRegularFile {
                print("Was a regular file")
            } else if wrapper.isDirectory {
                print("Was a directory")
            }
            if let attributedString = NSAttributedString(rtfdFileWrapper: wrapper, documentAttributes: nil) {
                self.textStorage?.insert(attributedString, at: self.selectedRange().location)
                return true
            } else if wrapper.isRegularFile {
                let decoder = JSONDecoder()
                let content = try! decoder.decode(AttachmentType.self, from: wrapper.regularFileContents!)
                let attachment = NSTextAttachment(fileWrapper: wrapper)
                attachment.attachmentCell = ViewAttachmentCell(content: content)
                let string = NSAttributedString(attachment: attachment)
                self.textStorage?.insert(string, at: self.selectedRange().location)
                return true
            }
            return super.readSelection(from: pboard, type: type)
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
