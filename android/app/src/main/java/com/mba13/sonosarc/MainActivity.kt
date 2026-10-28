package com.mba13.sonosarc

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import java.text.DateFormat
import java.util.Date

class MainActivity : ComponentActivity() {
    private val viewModel: ArcViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            MaterialTheme {
                val state by viewModel.state.collectAsState()
                DisposableEffect(Unit) {
                    viewModel.startPolling()
                    onDispose { viewModel.stopPolling() }
                }
                ArcScreen(
                    state = state,
                    onDiscover = viewModel::discover,
                    onManualIp = viewModel::setManualIp,
                    onConnectManual = viewModel::connectManual,
                    onConnect = viewModel::connect,
                    onNight = viewModel::setNight,
                    onSpeech = viewModel::setSpeech,
                    onRefresh = viewModel::refresh,
                    onForget = viewModel::forget,
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ArcScreen(
    state: ArcUiState,
    onDiscover: () -> Unit,
    onManualIp: (String) -> Unit,
    onConnectManual: () -> Unit,
    onConnect: (SonosSpeaker) -> Unit,
    onNight: (Boolean) -> Unit,
    onSpeech: (Boolean) -> Unit,
    onRefresh: () -> Unit,
    onForget: () -> Unit,
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Sonos Arc") },
                actions = {
                    if (state.snapshot != null) {
                        TextButton(onClick = onRefresh, enabled = !state.isWorking) {
                            Text("Refresh")
                        }
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            val snapshot = state.snapshot
            if (snapshot == null) {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp)) {
                        Text("Control Night Mode and Speech Enhancement from a Home Screen widget.")
                        Text(
                            "Pick your Arc or Beam, then add the Sonos Arc widget.",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            } else {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("Selected speaker", style = MaterialTheme.typography.labelMedium)
                        Text(snapshot.speaker.displayTitle, style = MaterialTheme.typography.titleLarge)
                        Text(snapshot.speaker.displaySubtitle, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(
                            "Last checked ${DateFormat.getTimeInstance(DateFormat.MEDIUM).format(Date(snapshot.updatedAt))}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        snapshot.lastError?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                        state.pollError?.let { Text("Poll: $it", color = MaterialTheme.colorScheme.tertiary) }
                        TextButton(onClick = onForget) { Text("Choose a different speaker") }
                    }
                }
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp)) {
                        ModeRow("Night Mode", snapshot.nightMode, !state.isWorking, onNight)
                        Spacer(Modifier.height(8.dp))
                        ModeRow("Speech Enhancement", snapshot.speechEnhancement, !state.isWorking, onSpeech)
                    }
                }
            }

            Card(modifier = Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("Find speaker", fontWeight = FontWeight.SemiBold)
                    Button(
                        onClick = onDiscover,
                        enabled = !state.isDiscovering,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        if (state.isDiscovering) {
                            CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                        } else {
                            Text("Discover Sonos")
                        }
                    }
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedTextField(
                            value = state.manualIp,
                            onValueChange = onManualIp,
                            modifier = Modifier.weight(1f),
                            label = { Text("Or enter IP") },
                            placeholder = { Text("192.168.1.50") },
                            singleLine = true,
                        )
                        TextButton(
                            onClick = onConnectManual,
                            enabled = state.manualIp.isNotBlank() && !state.isWorking,
                        ) {
                            Text("Connect")
                        }
                    }
                    state.speakers.forEach { speaker ->
                        TextButton(
                            onClick = { onConnect(speaker) },
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Column(Modifier.fillMaxWidth()) {
                                Text(speaker.displayTitle, fontWeight = FontWeight.Medium)
                                Text(
                                    speaker.displaySubtitle + if (speaker.looksLikeSoundbar) "  · Soundbar" else "",
                                    style = MaterialTheme.typography.bodySmall,
                                )
                            }
                        }
                    }
                }
            }

            state.message?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun ModeRow(title: String, on: Boolean, enabled: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title)
        Switch(checked = on, onCheckedChange = onChange, enabled = enabled)
    }
}
