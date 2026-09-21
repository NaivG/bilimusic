import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/app/shells/shell_page_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/core/network/bili_exception.dart';
import 'package:bilimusic/core/network/passport_client.dart';
import 'package:bilimusic/features/auth/captcha_helper.dart';
import 'package:bilimusic/shared/utils/platform_helper.dart';
import 'package:bilimusic/features/auth/ui/qr_login_widget.dart';

enum _LoginMode { sms, password, qr }

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  _LoginMode _mode = PlatformHelper.isDesktop ? _LoginMode.qr : _LoginMode.sms;
  String _selectedCountry = '中国大陆';
  String _countryId = '86';
  int _cid = 1; // 添加数据库ID字段
  String _phoneNumber = '';
  String _password = '';
  String _captcha = '';
  bool _isLoading = false;
  bool _isCaptchaSent = false;

  // 验证相关参数
  String _captchaToken = '';
  String _gt = '';
  String _challenge = '';
  String _captchaKey = '';

  // 国际冠字码列表
  List<Map<String, dynamic>> _countries = [];

  final CaptchaHelper _captchaHelper = CaptchaHelper();
  final PassportClient _passport = PassportClient();

  @override
  void initState() {
    super.initState();
    _loadCountries();
  }

  @override
  void dispose() {
    _passport.close();
    super.dispose();
  }

  // 加载国家列表
  Future<void> _loadCountries() async {
    // 跨 async gap 前先取好 messenger，避免 use_build_context_synchronously
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _isLoading = true;
    });

    try {
      final data = await _passport.get('/web/generic/country/list');

      final commonCountries = List<Map<String, dynamic>>.from(
        data['common'].map(
          (item) => {
            'id': item['id'], // 数据库ID，用于提交到API
            'cname': item['cname'],
            'country_id': item['country_id'], // 国际冠字码，用于显示
          },
        ),
      );

      final otherCountries = List<Map<String, dynamic>>.from(
        data['others'].map(
          (item) => {
            'id': item['id'], // 数据库ID，用于提交到API
            'cname': item['cname'],
            'country_id': item['country_id'], // 国际冠字码，用于显示
          },
        ),
      );

      setState(() {
        _countries = [...commonCountries, ...otherCountries];
        if (_countries.isNotEmpty) {
          _selectedCountry = _countries[0]['cname'];
          _countryId = _countries[0]['country_id'];
          _cid = _countries[0]['id']; // 设置数据库ID
        }
      });
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('加载国家列表失败: $e')));
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 获取验证码
  Future<void> _getCaptcha() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _isLoading = true;
    });

    try {
      final captchaData = await _captchaHelper.getCaptchaData();
      if (captchaData != null) {
        setState(() {
          _captchaToken = captchaData['token'];
          _gt = captchaData['gt'];
          _challenge = captchaData['challenge'];
        });

        // 启动极验验证
        _captchaHelper.startCaptcha(
          _gt,
          _challenge,
          CaptchaCallback(
            onResult: (result) {
              // 极验验证成功，继续发送短信验证码
              _sendSmsCode(result);
            },
            onError: (message) {
              setState(() {
                _isLoading = false;
              });
              messenger.showSnackBar(
                SnackBar(content: Text('人机验证失败: ${message.toString()}')),
              );
            },
          ),
        );
      } else {
        messenger.showSnackBar(SnackBar(content: Text('获取验证码失败')));
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('获取验证码失败: $e')));
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 发送短信验证码
  Future<void> _sendSmsCode(Map<String, String> validateResult) async {
    final messenger = ScaffoldMessenger.of(context);
    if (_phoneNumber.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text('请输入手机号')));
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      debugPrint(validateResult.toString());
      final requester = {
        'cid': _countryId,
        'tel': _phoneNumber,
        'source': 'main-fe-header',
        'token': _captchaToken,
        'challenge': validateResult['geetest_challenge'] ?? '',
        'validate': validateResult['geetest_validate'] ?? '',
        'seccode': validateResult['geetest_seccode'] ?? '',
      };
      debugPrint(requester.toString());
      final data = await _passport.postForm(
        '/x/passport-login/web/sms/send',
        body: requester,
      );

      setState(() {
        _isCaptchaSent = true;
        _captchaKey = data['captcha_key'];
      });

      messenger.showSnackBar(SnackBar(content: Text('短信验证码已发送')));
    } on BiliException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('发送验证码失败: ${e.message}(${e.code})')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('发送验证码失败: $e')));
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 短信登录
  Future<void> _smsLogin() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_phoneNumber.isEmpty || _captcha.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text('请输入手机号和验证码')));
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final data = await _passport.postForm(
        '/x/passport-login/web/login/sms',
        body: {
          'cid': _countryId, // 使用数据库ID而不是国际冠字码
          'tel': _phoneNumber,
          'code': _captcha,
          'source': 'main-fe-header',
          'captcha_key': _captchaKey,
          'go_url': "https://www.bilibili.com/",
        },
      );

      await _onLoginSucceeded(data);

      messenger.showSnackBar(SnackBar(content: Text('登录成功')));

      ShellPageManager.instance.pop(); // 返回上一页
    } on BiliException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('登录失败: ${e.message}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('登录失败: $e')));
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 获取公钥和盐
  Future<Map<String, dynamic>?> _getPublicKey() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final data = await _passport.get('/x/passport-login/web/key');
      return {'hash': data['hash'], 'key': data['key']};
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('获取公钥失败: $e')));
    }
    return null;
  }

  // 密码登录
  Future<void> _passwordLogin() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_phoneNumber.isEmpty || _password.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text('请输入账号和密码')));
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // 1. 获取验证码（人机验证）
      final captchaData = await _captchaHelper.getCaptchaData();
      if (captchaData == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _captchaToken = captchaData['token'];
        _gt = captchaData['gt'];
        _challenge = captchaData['challenge'];
      });

      // 启动极验验证
      _captchaHelper.startCaptcha(
        _gt,
        _challenge,
        CaptchaCallback(
          onResult: (result) async {
            // 极验验证成功，继续密码登录
            await _doPasswordLogin(result);
          },
          onError: (message) {
            setState(() {
              _isLoading = false;
            });
            messenger.showSnackBar(
              SnackBar(content: Text('人机验证失败: ${message.toString()}')),
            );
          },
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('登录失败: $e')));
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 执行密码登录
  Future<void> _doPasswordLogin(Map<String, String> validateResult) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      // 2. 获取公钥和盐（盐 20 秒有效，必须贴着提交取——极验已在前面过完）
      final keyInfo = await _getPublicKey();
      if (keyInfo == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // 3. 加密密码：base64(RSA_PKCS1(盐 + 明文密码))。
      //    不是旧的 sha256(盐 + 密码)——服务端已不认，会一直报密码错误。
      final encryptedPassword = PassportClient.encryptPassword(
        keyInfo['key']!.toString(),
        keyInfo['hash']!.toString(),
        _password,
      );

      // 4. 登录
      final data = await _passport.postForm(
        '/x/passport-login/web/login',
        body: {
          'username': _phoneNumber,
          'password': encryptedPassword,
          'keep': '0',
          'token': _captchaToken,
          'challenge': validateResult['geetest_challenge'] ?? '',
          'validate': validateResult['geetest_validate'] ?? '',
          'seccode': validateResult['geetest_seccode'] ?? '',
          'source': 'main-fe-header',
        },
      );

      // code == 0 但 status != 0 是风控分支：服务端要求用绑定手机号做安全
      // 验证（「手机号验证」，完整闭环要走 /x/safecenter/*，本端未接入），
      // 这里如实提示并引导改用扫码登录。
      //
      // 一般撞这个是正常的，用扫码和验证码登录一次就可以了。
      final status = (data['status'] as num?)?.toInt() ?? 0;
      if (status != 0) {
        final message = data['message']?.toString() ?? '本次登录环境存在风险，请改用扫码登录';
        messenger.showSnackBar(SnackBar(content: Text(message)));
        return;
      }

      await _onLoginSucceeded(data);

      messenger.showSnackBar(SnackBar(content: Text('登录成功')));

      ShellPageManager.instance.pop(); // 返回上一页
    } on BiliException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('登录失败: ${e.message}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('登录失败: $e')));
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 登录成功后的收尾：把 passport 下发的 refresh_token 落盘。
  ///
  /// Cookie 已由 PassportClient 统一回收；refresh_token 是响应体里的
  /// **非 Cookie** 刷新凭据（SESSDATA 续期要用），落盘失败不影响本次登录。
  Future<void> _onLoginSucceeded(Map<String, dynamic> data) async {
    final token = data['refresh_token']?.toString() ?? '';
    if (token.isEmpty) return;
    try {
      await ref.read(passportStoreProvider).setRefreshToken(token);
    } catch (e) {
      debugPrint('[Login] refresh_token 落盘失败: $e');
    }
  }

  // 选择国家
  void _selectCountry() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.5,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  '选择国家/地区',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _countries.length,
                  itemBuilder: (context, index) {
                    final country = _countries[index];
                    return ListTile(
                      title: Text(country['cname']),
                      subtitle: Text('+${country['country_id']}'),
                      onTap: () {
                        setState(() {
                          _selectedCountry = country['cname'];
                          _countryId = country['country_id'];
                          _cid = country['id']; // 更新数据库ID
                        });
                        ShellPageManager.instance.pop();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQrTab() {
    return QrLoginWidget(
      onSuccess: () {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('登录成功')));
        ShellPageManager.instance.pop();
      },
    );
  }

  Widget _buildSmsOrPasswordTab() {
    final isSms = _mode == _LoginMode.sms;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 国家/地区选择
          if (isSms) ...[
            ListTile(
              title: Text('国家/地区'),
              subtitle: Text('$_selectedCountry (+$_countryId)'),
              trailing: Icon(Icons.arrow_forward_ios),
              onTap: _selectCountry,
            ),
            SizedBox(height: 10),
          ],

          // 手机号/账号输入
          TextFormField(
            decoration: InputDecoration(
              labelText: isSms ? '手机号' : '账号',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.phone),
            ),
            keyboardType: TextInputType.phone,
            onChanged: (value) => _phoneNumber = value,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return isSms ? '请输入手机号' : '请输入账号';
              }
              return null;
            },
          ),
          SizedBox(height: 10),

          // 密码输入（仅密码登录）
          if (!isSms) ...[
            TextFormField(
              decoration: InputDecoration(
                labelText: '密码',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
              obscureText: true,
              onChanged: (value) => _password = value,
              validator: (value) {
                if (!isSms && (value == null || value.isEmpty)) {
                  return '请输入密码';
                }
                return null;
              },
            ),
            SizedBox(height: 20),
          ],

          // 验证码输入（仅短信登录）
          if (isSms) ...[
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    decoration: InputDecoration(
                      labelText: '验证码',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.security),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (value) => _captcha = value,
                    validator: (value) {
                      if (isSms &&
                          _isCaptchaSent &&
                          (value == null || value.isEmpty)) {
                        return '请输入验证码';
                      }
                      return null;
                    },
                  ),
                ),
                SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _isCaptchaSent ? null : _getCaptcha,
                  child: Text(_isCaptchaSent ? '已发送' : '获取验证码'),
                ),
              ],
            ),
            SizedBox(height: 20),
          ],

          // 登录按钮
          ElevatedButton(
            onPressed: _isLoading
                ? null
                : (isSms
                      ? (_isCaptchaSent ? _smsLogin : _getCaptcha)
                      : _passwordLogin),
            child: _isLoading
                ? CircularProgressIndicator()
                : Text(isSms ? (_isCaptchaSent ? '登录' : '获取验证码') : '登录'),
            style: ElevatedButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('登录')),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 切换登录方式
            SegmentedButton<_LoginMode>(
              segments: const [
                ButtonSegment(value: _LoginMode.sms, label: Text('短信登录')),
                ButtonSegment(value: _LoginMode.password, label: Text('密码登录')),
                ButtonSegment(value: _LoginMode.qr, label: Text('扫码登录')),
              ],
              selected: {_mode},
              onSelectionChanged: (Set<_LoginMode> newSelection) {
                setState(() {
                  _mode = newSelection.first;
                });
              },
            ),
            SizedBox(height: 20),
            if (_mode == _LoginMode.qr)
              _buildQrTab()
            else
              _buildSmsOrPasswordTab(),
          ],
        ),
      ),
    );
  }
}
