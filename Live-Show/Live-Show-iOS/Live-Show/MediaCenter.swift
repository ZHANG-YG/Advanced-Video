//
//  MediaCenter.swift
//  Live-Show
//
//  Created by GongYuhua on 2019/2/25.
//  Copyright © 2019 Agora. All rights reserved.
//

import Foundation
import AgoraRtcEngineKit

protocol MediaCenterDelegate: NSObjectProtocol {
    func mediaCenter(_ center: MediaCenter, didJoinChannel channel: String)
    func mediaCenter(_ center: MediaCenter, didRemoteVideoDecoded channel: String)
}

class MediaCenter: NSObject {
    fileprivate lazy var agoraKit: AgoraRtcEngineKit = {
        let agoraKit = AgoraRtcEngineKit.sharedEngine(withAppId: <#AppID#>, delegate: self)
        agoraKit.setChannelProfile(.liveBroadcasting)
        agoraKit.setClientRole(.audience)
        agoraKit.enableVideo()
        agoraKit.setVideoEncoderConfiguration(
            AgoraVideoEncoderConfiguration(
                size: AgoraVideoDimension960x720,
                frameRate: .fps24,
                bitrate: AgoraVideoBitrateStandard,
                orientationMode: .adaptative
            )
        )
        agoraKit.setLogFile(MediaCenter.document() + "/agoralog.txt")
        agoraKit.setLogFilter(95585)
        print("version: \(AgoraRtcEngineKit.getSdkVersion())")
        return agoraKit
    }()
    
    static func document() -> String {
        #if os(iOS)
        let cacheDirectory = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        #else
        let cacheDirectory = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first!
        #endif
        let path = cacheDirectory + "/AgoraLogs"
        
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        if !exists || !isDirectory.boolValue {
            try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
        }
        
        return path
    }
    
    var channel: Channel?
    var renderView: UIView?
    weak var delegate: MediaCenterDelegate?
    
    init(delegate: MediaCenterDelegate) {
        super.init()
        self.delegate = delegate
    }
    
    func joinChannel(_ channel: Channel, renderView: UIView) {
        agoraKit.joinChannel(byToken: nil, channelId: channel.channelName, info: nil, uid: 0, joinSuccess: nil)
        
        self.channel = channel
        self.renderView = renderView
        
        let canvas = AgoraRtcVideoCanvas()
        canvas.uid = channel.hostUid
        canvas.view = renderView
        canvas.renderMode = .hidden
        agoraKit.setupRemoteVideo(canvas)
    }
    
    func leaveChannel(_ channel: Channel) {
        agoraKit.leaveChannel(nil)
        
        let emptyCanvas = AgoraRtcVideoCanvas()
        emptyCanvas.uid = channel.hostUid
        emptyCanvas.view = nil
        agoraKit.setupRemoteVideo(emptyCanvas)
        
        self.channel = nil
        self.renderView = nil
    }
}

extension MediaCenter: AgoraRtcEngineDelegate {
    func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinChannel channel: String, withUid uid: UInt, elapsed: Int) {
        delegate?.mediaCenter(self, didJoinChannel: channel)
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinedOfUid uid: UInt, elapsed: Int) {
        guard let channel = channel, uid == channel.hostUid else {
            return
        }
        delegate?.mediaCenter(self, didRemoteVideoDecoded: channel.channelName)
        print("didJoinedOfUid: \(uid)")
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, firstRemoteVideoDecodedOfUid uid: UInt, size: CGSize, elapsed: Int) {
        print("firstRemoteVideoDecodedOfUid: \(uid)")
    }
}
