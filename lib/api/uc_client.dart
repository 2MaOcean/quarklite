import 'quark_client.dart';

/// UC 网盘客户端（实验性）。
///
/// UC 网盘（drive.uc.cn）与夸克同属一个网盘 API 家族，接口路径、参数、
/// 响应结构基本一致，因此直接继承 [QuarkClient]，只覆盖域名与 Referer。
/// 登录方式与夸克一致：粘贴网页端登录后的 Cookie。
///
/// 注意：UC 的接口细节未经过充分真机验证，如遇到字段/路径差异，
/// 需要按实际响应微调。
class UcClient extends QuarkClient {
  @override
  String get driveApi => 'https://drive.uc.cn/1/clouddrive';

  @override
  String get drivePcApi => 'https://drive.uc.cn/1/clouddrive';

  @override
  String get panApi => 'https://pan.uc.cn';

  @override
  String get refererBase => 'https://pan.uc.cn/';
}
