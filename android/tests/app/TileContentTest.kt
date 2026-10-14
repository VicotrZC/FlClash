package com.follow.clash

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * 磁贴显示规则：连接后标签位放节点名、副标题位放配置名；未连接时不显示节点名。
 * 这几条是用户可见的行为，单独测掉，免得以后改 TileService 时被无声改坏。
 */
class TileContentTest {
    @Test
    fun `connected shows the node as the label and the profile as the subtitle`() {
        val content = TileContent(
            runState = RunState.STARTED,
            nodeName = "HK 01",
            profileName = "Work",
        )

        assertEquals("HK 01", content.label)
        assertEquals("Work", content.subtitle)
    }

    @Test
    fun `disconnected keeps the node hidden and falls back to the profile name`() {
        val content = TileContent(
            runState = RunState.STOPPED,
            nodeName = "HK 01",
            profileName = "Work",
        )

        // 没连接时显示节点名会让人以为流量正走那个节点。
        assertEquals("Work", content.label)
        assertEquals("", content.subtitle)
    }

    @Test
    fun `starting and stopping also keep the node hidden`() {
        for (runState in listOf(RunState.STARTING, RunState.STOPPING)) {
            val content = TileContent(
                runState = runState,
                nodeName = "HK 01",
                profileName = "Work",
            )

            assertEquals(runState.name, "Work", content.label)
            assertEquals(runState.name, "", content.subtitle)
        }
    }

    @Test
    fun `connected without a node falls back to the profile name`() {
        val content = TileContent(
            runState = RunState.STARTED,
            nodeName = null,
            profileName = "Work",
        )

        assertEquals("Work", content.label)
        assertEquals("", content.subtitle)
    }

    @Test
    fun `connected with an empty node name falls back to the profile name`() {
        val content = TileContent(
            runState = RunState.STARTED,
            nodeName = "",
            profileName = "Work",
        )

        assertEquals("Work", content.label)
        assertEquals("", content.subtitle)
    }

    @Test
    fun `an empty profile name falls back to the app name`() {
        val content = TileContent(
            runState = RunState.STOPPED,
            nodeName = null,
            profileName = "",
        )

        assertEquals("FlClash", content.label)
    }

    @Test
    fun `connected with a node but no profile name has no subtitle`() {
        val content = TileContent(
            runState = RunState.STARTED,
            nodeName = "HK 01",
            profileName = "",
        )

        assertEquals("HK 01", content.label)
        assertEquals("", content.subtitle)
    }
}
