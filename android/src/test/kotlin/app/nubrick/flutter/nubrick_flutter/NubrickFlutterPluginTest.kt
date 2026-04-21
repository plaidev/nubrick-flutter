package app.nubrick.flutter.nubrick_flutter

import kotlin.test.assertEquals
import kotlin.test.Test

internal class NubrickFlutterPluginTest {
    @Test
    fun parseStackTraceElements_should_work() {
        val stackTraces = parseStackTraceElements(
            "#0      NubrickDispatcher.dispatch (package:nubrick_flutter/dispatcher.dart:10:5)\n" +
            "#1      _MyAppState.build.<anonymous closure> (package:nubrick_flutter_example/main.dart:91:42)"
        )

        val expected = listOf(
            StackTraceElement("NubrickDispatcher", "dispatch", "package:nubrick_flutter/dispatcher.dart", 10),
            StackTraceElement("unknown", "unknown", "package:nubrick_flutter_example/main.dart", 91)
        )

        assertEquals(expected.size, stackTraces.size)
        assertEquals(expected[0].fileName, stackTraces[0].fileName)
        assertEquals(expected[0].lineNumber, stackTraces[0].lineNumber)
        assertEquals(expected[1].fileName, stackTraces[1].fileName)
        assertEquals(expected[1].lineNumber, stackTraces[1].lineNumber)
    }

}
