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
static  unsigned char mRecordingAudioAppPool[kAudioBufferPoolSize];
static  unsigned char mRecordingAudioMicPool[kAudioBufferPoolSize];
static int mRecordingAppBufferBytes = 0;
static int mRecordingMicBufferBytes = 0;
static CriticalSectionWrapper *CritSect = CriticalSectionWrapper::CreateCriticalSection();

static AudioConverterRef mAudioConverterRef;

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
//    AudioBufferList inAudioBufferList = [self resamplingAudioBuffer:sampleBuffer];
//
//    AudioBuffer buffer = inAudioBufferList.mBuffers[0];
//    uint8_t* p = (uint8_t*)buffer.mData;
//    pushAudioAppFrame(p, buffer.mDataByteSize);
}
    
+ (void)pushAudioMicBuffer:(CMSampleBufferRef)sampleBuffer
{
//    AudioBufferList inAudioBufferList =
    [self resamplingAudioBuffer:sampleBuffer];
    
//    AudioBuffer buffer = inAudioBufferList.mBuffers[0];
//    uint8_t* p = (uint8_t*)buffer.mData;
    
//    pushAudioMicFrame(p, buffer.mDataByteSize);
}

+ (void)creatConverter {
    if (mAudioConverterRef) {
        return;
    }
}

+ (AudioBufferList)resamplingAudioBuffer:(CMSampleBufferRef)sampleBuffer {
    AudioStreamBasicDescription inAudioStreamBasicDescription = *CMAudioFormatDescriptionGetStreamBasicDescription((CMAudioFormatDescriptionRef)CMSampleBufferGetFormatDescription(sampleBuffer));
    
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
    
    //
    AudioConverterRef audioConverter;
    memset(&audioConverter, 0, sizeof(audioConverter));
    NSAssert(AudioConverterNew(&inAudioStreamBasicDescription, &outAudioStreamBasicDescription, &audioConverter) == 0, nil);
    
    //
    AudioBufferList inAudioBufferList;
    CMBlockBufferRef blockBuffer;
    CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, NULL, &inAudioBufferList, sizeof(inAudioBufferList), NULL, NULL, 0, &blockBuffer);
    
    uint32_t bufferSize = inAudioBufferList.mBuffers[0].mDataByteSize;
    NSLog(@"%u", bufferSize);
    
    uint8_t *buffer = (uint8_t *)malloc(bufferSize);
    memset(buffer, 0, bufferSize);
    
    AudioBufferList outAudioBufferList;
    outAudioBufferList.mNumberBuffers = 1;
    outAudioBufferList.mBuffers[0].mNumberChannels = 1;
    outAudioBufferList.mBuffers[0].mDataByteSize = bufferSize;
    outAudioBufferList.mBuffers[0].mData = buffer;
    
    UInt32 len = outAudioStreamBasicDescription.mBytesPerPacket / inAudioStreamBasicDescription.mBytesPerPacket;
    UInt32 bytes = 0;
    NSLog(@"len: %u", len);
    
    AudioConverterConvertBuffer(audioConverter,
                                len,
                                &inAudioBufferList,
                                &bytes,
                                &outAudioBufferList);
    
    AudioBuffer buffer2 = outAudioBufferList.mBuffers[0];
    uint8_t* p = (uint8_t*)buffer2.mData;
    
    pushAudioMicFrame(p, buffer2.mDataByteSize);
    
    
    free(buffer);
    CFRelease(blockBuffer);
//    AudioConverterDispose(audioConverter);
    
    return outAudioBufferList;
}

//OSStatus inInputDataProc(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData)
//{
//    AudioBufferList audioBufferList = *(AudioBufferList *)inUserData;
//
//    ioData->mBuffers[0].mData = audioBufferList.mBuffers[0].mData;
//    ioData->mBuffers[0].mDataByteSize = audioBufferList.mBuffers[0].mDataByteSize;
//
//    return  noErr;
//}
@end
