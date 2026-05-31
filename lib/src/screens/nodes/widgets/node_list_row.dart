import 'package:cake_wallet/routes.dart';
import 'package:cake_wallet/src/screens/nodes/widgets/node_indicator.dart';
import 'package:cake_wallet/src/widgets/standard_list.dart';
import 'package:cw_bitcoin/electrum.dart';
import 'package:cw_core/node.dart';
import 'package:cw_core/wallet_type.dart';
import 'package:cw_pivx/src/sapling/pivx_sapling_electrumx.dart';
import 'package:flutter/material.dart';

class NodeListRow extends StandardListRow {
  NodeListRow(
      {required String title,
      required this.node,
      required void Function(BuildContext context) onTap,
      required bool isSelected,
      required this.isPow})
      : super(title: title, onTap: onTap, isSelected: isSelected);

  final Node node;
  final bool isPow;

  @override
  Widget build(BuildContext context) {
    final leading = buildLeading(context);
    final trailing = buildTrailing(context);
    return Container(
      height: node.type == WalletType.pivx ? 68 : 56,
      padding: EdgeInsets.only(left: 12, right: 12, top: 2, bottom: 2),
      margin: EdgeInsets.only(top: 2, bottom: 2),
      child: FilledButton(
        onPressed: () => onTap?.call(context),
        style: FilledButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            leading,
            buildCenter(context, hasLeftOffset: true),
            trailing,
          ],
        ),
      ),
    );
  }

  @override
  Widget buildLeading(BuildContext context) {
    return FutureBuilder(
        future: _requestAndUpdateNodeStatus(),
        builder: (context, snapshot) {
          switch (snapshot.connectionState) {
            case ConnectionState.done:
              return NodeIndicator(isLive: snapshot.data ?? false);
            default:
              return NodeIndicator(isLive: false);
          }
        });
  }

  @override
  Widget buildCenter(BuildContext context, {required bool hasLeftOffset}) {
    if (node.type != WalletType.pivx) {
      return super.buildCenter(context, hasLeftOffset: hasLeftOffset);
    }

    final status = _pivxSaplingStatus;
    final detail = _pivxSaplingDetail;

    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          if (hasLeftOffset) SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: titleColor(context),
                        fontWeight:
                            isSelected ? FontWeight.w800 : FontWeight.w400,
                      ),
                ),
                SizedBox(height: 2),
                Text(
                  detail.isEmpty ? status : '$status - $detail',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: node.supportsPivxSapling == false
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  @override
  Widget buildTrailing(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pushNamed(
        isPow ? Routes.newPowNode : Routes.newNode,
        arguments: {'editingNode': node, 'isSelected': isSelected},
      ),
      child: Container(
        padding: EdgeInsets.all(10),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.surface,
        ),
        child: Icon(
          Icons.edit,
          size: 14,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  String get _pivxSaplingStatus {
    if (node.supportsPivxSapling == true) return 'Sapling ready';
    if (node.supportsPivxSapling == false) return 'Sapling unavailable';
    return 'Sapling not checked';
  }

  String get _pivxSaplingDetail {
    if (node.supportsPivxSapling != true) return '';

    final parts = <String>[
      if (node.pivxSaplingNetwork?.isNotEmpty ?? false)
        node.pivxSaplingNetwork!,
      if (node.pivxSaplingActivationHeight != null)
        'activation ${node.pivxSaplingActivationHeight}',
      if (node.pivxSaplingVersionLabel != 'PIVX Sapling')
        node.pivxSaplingVersionLabel,
    ];

    return parts.join(' / ');
  }

  Future<bool> _requestAndUpdateNodeStatus() async {
    final isAlive = await node.requestNode();
    if (node.type != WalletType.pivx) return isAlive;

    final lastCheckedAt = node.pivxSaplingLastCheckedAt;
    if (lastCheckedAt != null &&
        DateTime.now().difference(lastCheckedAt) < Duration(minutes: 5)) {
      return isAlive && node.supportsPivxSapling == true;
    }

    if (!isAlive) {
      await _savePivxSaplingStatus(null);
      return false;
    }

    final capabilities = await _pivxNodeSaplingCapabilities();
    await _savePivxSaplingStatus(capabilities);
    return capabilities?.supportsBlockRange == true;
  }

  Future<SaplingRpcCapabilities?> _pivxNodeSaplingCapabilities() async {
    final client = ElectrumClient();
    try {
      await client.connectToUri(node.uri, useSSL: node.useSSL);
      if (!client.isConnected) return null;

      return await _probePivxSapling(client, isTestnet: false) ??
          await _probePivxSapling(client, isTestnet: true);
    } catch (_) {
      return null;
    } finally {
      await client.close();
    }
  }

  Future<SaplingRpcCapabilities?> _probePivxSapling(
    ElectrumClient client, {
    required bool isTestnet,
  }) async {
    try {
      final capabilities = await PIVXSaplingElectrumX(
        electrumClient: client,
        isTestnet: isTestnet,
      ).probeCapabilities();
      return capabilities;
    } catch (_) {
      return null;
    }
  }

  Future<void> _savePivxSaplingStatus(
      SaplingRpcCapabilities? capabilities) async {
    node.supportsPivxSapling = capabilities?.supportsBlockRange ?? false;
    node.pivxSaplingContract = capabilities?.contract;
    node.pivxSaplingServerVersion = capabilities?.serverVersion;
    node.pivxCoreVersion = capabilities?.pivxCoreVersion;
    node.pivxSaplingNetwork = capabilities?.network;
    node.pivxSaplingActivationHeight = capabilities?.activationHeight;
    node.pivxSaplingLastCheckedAt = DateTime.now();

    if (node.isInBox) {
      await node.save();
    }
  }
}

class NodeHeaderListRow extends StandardListRow {
  NodeHeaderListRow(
      {required String title,
      required void Function(BuildContext context) onTap})
      : super(title: title, onTap: onTap, isSelected: false);

  @override
  Widget build(BuildContext context) {
    final leading = buildLeading(context);
    final trailing = buildTrailing(context);
    return Container(
      height: 56,
      padding: EdgeInsets.only(left: 12, right: 12, top: 2, bottom: 2),
      child: TextButton(
        onPressed: () => onTap?.call(context),
        style: ButtonStyle(
          backgroundColor:
              WidgetStateProperty.all(Theme.of(context).colorScheme.surface),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            if (leading != null) leading,
            buildCenter(context, hasLeftOffset: leading != null),
            trailing,
          ],
        ),
      ),
    );
  }

  @override
  Widget buildTrailing(BuildContext context) {
    return SizedBox(
      width: 20,
      child: Icon(Icons.add,
          color: Theme.of(context).colorScheme.onSurfaceVariant, size: 24.0),
    );
  }
}
