package com.example.personal_ai_assistant

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import android.os.Handler
import android.os.Looper

class SpeechChannel : FlutterPlugin, MethodChannel.MethodCallHandler, RecognitionListener {
    private lateinit var channel: MethodChannel
    private var speechRecognizer: SpeechRecognizer? = null
    private var context: Context? = null
    private var isListening = false
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "speech_recognition")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> {
                mainHandler.post {
                    if (SpeechRecognizer.isRecognitionAvailable(context!!)) {
                        speechRecognizer = SpeechRecognizer.createSpeechRecognizer(context)
                        speechRecognizer?.setRecognitionListener(this)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
            }
            "startListening" -> {
                val localeId = call.argument<String>("localeId") ?: "en-US"
                mainHandler.post {
                    startListening(localeId)
                    result.success(true)
                }
            }
            "stopListening" -> {
                mainHandler.post {
                    stopListening()
                    result.success(true)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun startListening(localeId: String) {
        if (isListening) return

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, localeId)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
        }

        speechRecognizer?.startListening(intent)
        isListening = true
        channel.invokeMethod("onStatusChanged", "listening")
    }

    private fun stopListening() {
        if (!isListening) return
        speechRecognizer?.stopListening()
        isListening = false
    }

    // RecognitionListener methods
    override fun onReadyForSpeech(params: Bundle?) {}
    override fun onBeginningOfSpeech() {}
    override fun onRmsChanged(rmsdB: Float) {}
    override fun onBufferReceived(buffer: ByteArray?) {}
    override fun onEndOfSpeech() {
        isListening = false
        channel.invokeMethod("onStatusChanged", "notListening")
    }

    override fun onError(error: Int) {
        isListening = false
        val message = when (error) {
            SpeechRecognizer.ERROR_AUDIO -> "Audio recording error"
            SpeechRecognizer.ERROR_CLIENT -> "Client side error"
            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Insufficient permissions"
            SpeechRecognizer.ERROR_NETWORK -> "Network error"
            SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "Network timeout"
            SpeechRecognizer.ERROR_NO_MATCH -> "No match"
            SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "Recognizer busy"
            SpeechRecognizer.ERROR_SERVER -> "Server error"
            SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "No speech input"
            else -> "Unknown error"
        }
        channel.invokeMethod("onError", message)
    }

    override fun onResults(results: Bundle?) {
        val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        if (!matches.isNullOrEmpty()) {
            val text = matches[0]
            channel.invokeMethod("onSpeechResult", mapOf("text" to text, "isFinal" to true))
            channel.invokeMethod("onStatusChanged", "done")
        }
    }

    override fun onPartialResults(partialResults: Bundle?) {
        val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        if (!matches.isNullOrEmpty()) {
            val text = matches[0]
            channel.invokeMethod("onSpeechResult", mapOf("text" to text, "isFinal" to false))
        }
    }

    override fun onEvent(eventType: Int, params: Bundle?) {}
}
