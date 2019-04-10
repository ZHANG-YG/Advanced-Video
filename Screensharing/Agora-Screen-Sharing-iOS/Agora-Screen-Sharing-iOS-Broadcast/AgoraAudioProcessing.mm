//
//  AGVideoPreProcessing.m
//  Agora-Screen-Sharing-iOS-Broadcast
//
//  Created by Alex Zheng on 7/28/16.
//  Copyright © 2016 Agora.io All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AgoraAudioProcessing.h"
#import "AgoraAudioCriticalSection.h"

#import <AgoraRtcEngineKit/IAgoraRtcEngine.h>
#import <AgoraRtcEngineKit/IAgoraMediaEngine.h>
#import <string.h>

static const int kAudioBufferPoolSize = 500000;
static unsigned char mRecordingAudioAppPool[kAudioBufferPoolSize];
static unsigned char mRecordingAudioMicPool[kAudioBufferPoolSize];
static int mRecordingAppBufferBytes = 0;
static int mRecordingMicBufferBytes = 0;
static CriticalSectionWrapper *CritSect = CriticalSectionWrapper::CreateCriticalSection();

static AudioConverterRef micAudioConverter = NULL;
static AudioStreamBasicDescription micInAudioStreamBasicDescription = {0};

static AudioConverterRef appAudioConverter = NULL;
static AudioStreamBasicDescription appInAudioStreamBasicDescription = {0};

void pushAudioAppFrame(unsigned char *inAudioFrame, int frameSize)
{
    CriticalSectionScoped lock(CritSect);
    
    int remainedSize = kAudioBufferPoolSize - mRecordingAppBufferBytes;
    if (remainedSize >= frameSize) {
        memcpy(mRecordingAudioAppPool+mRecordingAppBufferBytes, inAudioFrame, frameSize);
    } else {
        mRecordingAppBufferBytes = 0;
        memcpy(mRecordingAudioAppPool+mRecordingAppBufferBytes, inAudioFrame, frameSize);
    }
    
    mRecordingAppBufferBytes += frameSize;
}

void pushAudioMicFrame(unsigned char *inAudioFrame, int frameSize)
{
    CriticalSectionScoped lock(CritSect);
    
    int remainedSize = kAudioBufferPoolSize - mRecordingMicBufferBytes;
    if (remainedSize >= frameSize) {
        memcpy(mRecordingAudioMicPool+mRecordingMicBufferBytes, inAudioFrame, frameSize);
    } else {
        mRecordingMicBufferBytes = 0;
        memcpy(mRecordingAudioMicPool+mRecordingMicBufferBytes, inAudioFrame, frameSize);
    }
    
    mRecordingMicBufferBytes += frameSize;
}

class AgoraAudioFrameObserver : public agora::media::IAudioFrameObserver
{
public:
    virtual bool onRecordAudioFrame(AudioFrame& audioFrame) override
    {
        CriticalSectionScoped lock(CritSect);
        
        int bytes = audioFrame.samples * audioFrame.channels * audioFrame.bytesPerSample;
        
        if (mRecordingAppBufferBytes < bytes && mRecordingMicBufferBytes < bytes) {
            return false;
        }
        
        short *mixedBuffer = (short *)malloc(bytes);
        
        if (mRecordingAppBufferBytes >= bytes) {
            memcpy(mixedBuffer, mRecordingAudioAppPool, bytes);
            mRecordingAppBufferBytes -= bytes;
            memcpy(mRecordingAudioAppPool, mRecordingAudioAppPool+bytes, mRecordingAppBufferBytes);
            
            if (mRecordingMicBufferBytes >= bytes) {
                short *micBuffer = (short *)mRecordingAudioMicPool;
                for (int i = 0; i < bytes / 2; ++i) {
                    
                    int number = mixedBuffer[i] / 4;
                    number += micBuffer[i];
                    
                    if (number > 32767) {
                        number = 32767;
                    } else if (number < -32768) {
                        number = -32768;
                    }
                    
                    mixedBuffer[i] = number;
                }
                
                mRecordingMicBufferBytes -= bytes;
                memcpy(mRecordingAudioMicPool, mRecordingAudioMicPool+bytes, mRecordingMicBufferBytes);
            }
        } else if (mRecordingMicBufferBytes >= bytes) {
            memcpy(mixedBuffer, mRecordingAudioMicPool, bytes);
            mRecordingMicBufferBytes -= bytes;
            memcpy(mRecordingAudioMicPool, mRecordingAudioMicPool+bytes, mRecordingMicBufferBytes);
        }
        
        memcpy(audioFrame.buffer, mixedBuffer, bytes);
        free(mixedBuffer);
        
        return true;
    }
    
    virtual bool onPlaybackAudioFrame(AudioFrame& audioFrame) override {
        return true;
    }
    
    virtual bool onMixedAudioFrame(AudioFrame& audioFrame) override {
        return true;
    }
    
    virtual bool onPlaybackAudioFrameBeforeMixing(unsigned int uid, AudioFrame& audioFrame) override {
        return true;
    }
};

static AgoraAudioFrameObserver s_audioFrameObserver;

@implementation AgoraAudioProcessing
+ (void)registerAudioPreprocessing: (AgoraRtcEngineKit*) kit
{
    if (!kit) {
        return;
    }
    
    agora::rtc::IRtcEngine* rtc_engine = (agora::rtc::IRtcEngine*)kit.getNativeHandle;
    agora::util::AutoPtr<agora::media::IMediaEngine> mediaEngine;
    mediaEngine.queryInterface(rtc_engine, agora::AGORA_IID_MEDIA_ENGINE);
    if (mediaEngine) {
        mediaEngine->registerAudioFrameObserver(&s_audioFrameObserver);
    }
}

+ (void)deregisterAudioPreprocessing:(AgoraRtcEngineKit*)kit
{
    if (!kit) {
        return;
    }
    
    agora::rtc::IRtcEngine* rtc_engine = (agora::rtc::IRtcEngine*)kit.getNativeHandle;
    agora::util::AutoPtr<agora::media::IMediaEngine> mediaEngine;
    mediaEngine.queryInterface(rtc_engine, agora::AGORA_IID_MEDIA_ENGINE);
    if (mediaEngine) {
        mediaEngine->registerAudioFrameObserver(NULL);
    }
}

+ (void)pushAudioAppBuffer:(CMSampleBufferRef)sampleBuffer
{
    AudioBufferList inAudioBufferList;
    CMBlockBufferRef blockBuffer = nil;
    OSStatus status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, NULL, &inAudioBufferList, sizeof(inAudioBufferList), NULL, NULL, 0, &blockBuffer);
    if (status != noErr) {
        return;
    }
    return;
//    AudioBuffer buffer = inAudioBufferList.mBuffers[0];
//    uint8_t* p = (uint8_t*)buffer.mData;
//
//    for (int i = 0; i < buffer.mDataByteSize; i += 2) {
//        uint8_t tmp;
//        tmp = p[i];
//        p[i] = p[i + 1];
//        p[i + 1] = tmp;
//    }
//    pushAudioAppFrame(p, buffer.mDataByteSize);
//
//    if (blockBuffer) {
//        CFRelease(blockBuffer);
//    }
}

+ (void)pushAudioMicBuffer:(CMSampleBufferRef)sampleBuffer
{
    [self checkMicConverterForBuffer:sampleBuffer];
    [self pushResamplingBuffer:sampleBuffer
                 withConverter:micAudioConverter];
}

+ (void)checkMicConverterForBuffer:(CMSampleBufferRef)sampleBuffer {
    AudioStreamBasicDescription inASBD = *CMAudioFormatDescriptionGetStreamBasicDescription((CMAudioFormatDescriptionRef)CMSampleBufferGetFormatDescription(sampleBuffer));
    if ([self checkEqualOfASBD:inASBD withASBD:micInAudioStreamBasicDescription] && micAudioConverter) {
        return;
    }
    
    if (micAudioConverter) {
        AudioConverterDispose(micAudioConverter);
        micAudioConverter = NULL;
    }
    micAudioConverter = [self createAudioConverterFrom:inASBD];
    if (micAudioConverter) {
        micInAudioStreamBasicDescription = inASBD;
    }
}

+ (AudioConverterRef)createAudioConverterFrom:(AudioStreamBasicDescription)inStreamBasicDescription
{
    AudioStreamBasicDescription outAudioStreamBasicDescription = {0};
    outAudioStreamBasicDescription.mSampleRate = 44100;
    outAudioStreamBasicDescription.mFormatID = kAudioFormatLinearPCM;
    outAudioStreamBasicDescription.mFormatFlags = kAudioFormatFlagIsPacked | kAudioFormatFlagIsSignedInteger;
    outAudioStreamBasicDescription.mBytesPerPacket = 2;
    outAudioStreamBasicDescription.mFramesPerPacket = 1;
    outAudioStreamBasicDescription.mBytesPerFrame = 2;
    outAudioStreamBasicDescription.mChannelsPerFrame = 1;
    outAudioStreamBasicDescription.mBitsPerChannel = 16;
    outAudioStreamBasicDescription.mReserved = 0;
    
    AudioConverterRef converter;
    memset(&converter, 0, sizeof(converter));
    AudioConverterNew(&inStreamBasicDescription, &outAudioStreamBasicDescription, &converter);
    return converter;
}

+ (BOOL)checkEqualOfASBD:(AudioStreamBasicDescription)aASBD withASBD:(AudioStreamBasicDescription)bASBD
{
    return (aASBD.mSampleRate == bASBD.mSampleRate)
    && (aASBD.mFormatID == bASBD.mFormatID)
    && (aASBD.mFormatFlags == bASBD.mFormatFlags)
    && (aASBD.mBytesPerPacket == bASBD.mBytesPerPacket)
    && (aASBD.mFramesPerPacket == bASBD.mFramesPerPacket)
    && (aASBD.mBytesPerFrame == bASBD.mBytesPerFrame)
    && (aASBD.mChannelsPerFrame == bASBD.mChannelsPerFrame)
    && (aASBD.mBitsPerChannel == bASBD.mBitsPerChannel)
    && (aASBD.mReserved == bASBD.mReserved);
}

+ (void)pushResamplingBuffer:(CMSampleBufferRef)sampleBuffer
               withConverter:(AudioConverterRef)converter
{
    if (!converter) {
        return;
    }
    
    AudioBufferList inAudioBufferList;
    CMBlockBufferRef blockBuffer;
    CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, NULL, &inAudioBufferList, sizeof(inAudioBufferList), NULL, NULL, 0, &blockBuffer);
    
    uint32_t bufferSize = 192000;
    uint8_t *buffer = (uint8_t *)malloc(bufferSize);
    memset(buffer, 0, bufferSize);
    
    AudioBufferList outAudioBufferList;
    outAudioBufferList.mNumberBuffers = 1;
    outAudioBufferList.mBuffers[0].mNumberChannels = 1;
    outAudioBufferList.mBuffers[0].mDataByteSize = bufferSize;
    outAudioBufferList.mBuffers[0].mData = buffer;
    
    UInt32 len = inAudioBufferList.mBuffers[0].mDataByteSize;
    UInt32 bytes = len;
    
    OSStatus err = AudioConverterConvertBuffer(converter,
                                               len,
                                               inAudioBufferList.mBuffers[0].mData,
                                               &bytes,
                                               outAudioBufferList.mBuffers[0].mData);
    
    if (!err) {
        AudioBuffer buffer2 = outAudioBufferList.mBuffers[0];
        uint8_t* p = (uint8_t*)buffer2.mData;
        pushAudioMicFrame(p, bytes);
    }
    
    free(buffer);
    if (blockBuffer) {
        CFRelease(blockBuffer);
    }
}
@end
