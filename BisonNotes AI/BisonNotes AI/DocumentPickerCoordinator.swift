//
//  DocumentPickerCoordinator.swift
//  Audio Journal
//
//  Handles document picker for audio file import
//

import Foundation
import UIKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Document Picker Coordinator

class DocumentPickerCoordinator: NSObject, ObservableObject {
    @Published var selectedURLs: [URL] = []
    @Published var isShowingPicker = false
    
    private var completionHandler: (([URL]) -> Void)?
    
    func selectAudioFiles(completion: @escaping ([URL]) -> Void) {
        self.completionHandler = completion
        self.isShowingPicker = true
    }
    
    func handleSelectedURLs(_ urls: [URL]) {
        selectedURLs = urls
        completionHandler?(urls)
        completionHandler = nil
        isShowingPicker = false
    }
}

// MARK: - Document Picker View Controller

class AudioDocumentPickerViewController: UIDocumentPickerViewController {
    private let coordinator: DocumentPickerCoordinator
    
    init(coordinator: DocumentPickerCoordinator) {
        self.coordinator = coordinator
        
        // Create supported audio types
        var supportedTypes: [UTType] = [UTType.audio]
        
        // Add specific audio formats if available
        if let m4aType = UTType(filenameExtension: "m4a") {
            supportedTypes.append(m4aType)
        }
        if let mp3Type = UTType(filenameExtension: "mp3") {
            supportedTypes.append(mp3Type)
        }
        if let wavType = UTType(filenameExtension: "wav") {
            supportedTypes.append(wavType)
        }
        
        super.init(forOpeningContentTypes: supportedTypes, asCopy: true)
        
        self.delegate = coordinator
        self.allowsMultipleSelection = true
        self.shouldShowFileExtensions = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Document Picker Delegate

extension DocumentPickerCoordinator: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        // Handle the selected URLs
        handleSelectedURLs(urls)
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        // Handle cancellation
        handleSelectedURLs([])
    }
}

// MARK: - SwiftUI Document Picker

struct AudioDocumentPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let coordinator: DocumentPickerCoordinator
    
    func makeUIViewController(context: Context) -> AudioDocumentPickerViewController {
        return AudioDocumentPickerViewController(coordinator: coordinator)
    }
    
    func updateUIViewController(_ uiViewController: AudioDocumentPickerViewController, context: Context) {
        // No updates needed
    }
} 