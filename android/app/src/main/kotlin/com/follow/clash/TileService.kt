package com.follow.clash

import android.annotation.SuppressLint
import android.os.Build
import android.service.quicksettings.Tile
import com.follow.clash.common.QuickAction
import com.follow.clash.common.quickIntent
import com.follow.clash.common.toPendingIntent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch

class TileService : android.service.quicksettings.TileService() {
    private var scope: CoroutineScope? = null

    override fun onStartListening() {
        super.onStartListening()
        scope?.cancel()
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate).also { scope ->
            scope.launch {
                combine(
                    ServiceState.runState,
                    ServiceState.currentNodeName,
                    ServiceState.currentProfileName,
                ) { runState, nodeName, profileName ->
                    TileContent(runState, nodeName, profileName)
                }.collect(::updateTile)
            }
        }
    }

    // Always route through QuickActionActivity: startActivityAndCollapse is
    // what closes the shade, so toggling the service in place would leave
    // the panel open after a tap.
    override fun onClick() {
        super.onClick()
        openQuickAction()
    }

    override fun onStopListening() {
        scope?.cancel()
        scope = null
        super.onStopListening()
    }

    private fun updateTile(content: TileContent) {
        qsTile?.apply {
            // 标签位放节点名，让用户不用打开 App 就能看出当前用的是哪个节点；
            // 未连接（或还没选节点）时回退到配置名 / 应用名。
            label = content.label
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                subtitle = content.subtitle
            }
            state = when (content.runState) {
                RunState.STARTED -> Tile.STATE_ACTIVE
                RunState.STARTING, RunState.STOPPING -> Tile.STATE_UNAVAILABLE
                RunState.STOPPED -> Tile.STATE_INACTIVE
            }
            updateTile()
        }
    }

    @SuppressLint("StartActivityAndCollapseDeprecated")
    private fun openQuickAction() {
        val intent = QuickAction.TOGGLE.quickIntent
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startActivityAndCollapse(intent.toPendingIntent)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}

/**
 * 磁贴要显示的内容。连接后才显示节点名——没连接时显示节点名会误导用户
 * 以为流量正走那个节点。
 */
internal data class TileContent(
    val runState: RunState,
    val nodeName: String?,
    val profileName: String,
) {
    private val connected = runState == RunState.STARTED

    val label: String
        get() {
            if (!connected) {
                return profileName.ifEmpty { FALLBACK_LABEL }
            }
            return nodeName?.takeIf { it.isNotEmpty() }
                ?: profileName.ifEmpty { FALLBACK_LABEL }
        }

    /** 连接后副标题给出配置名作为上下文；未连接时副标题留空。 */
    val subtitle: String
        get() {
            if (!connected) {
                return ""
            }
            val node = nodeName?.takeIf { it.isNotEmpty() }
            return if (node == null || profileName.isEmpty()) "" else profileName
        }

    private companion object {
        const val FALLBACK_LABEL = "FlClash"
    }
}
