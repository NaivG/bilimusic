import 'dart:convert';
import 'package:bilimusic/shells/shell_page_manager.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:bilimusic/utils/network_config.dart';
import 'package:bilimusic/utils/captcha_helper.dart';
import 'package:bilimusic/utils/platform_helper.dart';
import 'package:bilimusic/pages/qr_login_widget.dart';

enum _LoginMode { sms, password, qr }

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
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

  @override
  void initState() {
    super.initState();
    _loadCountries();
  }

  // 加载国家列表
  Future<void> _loadCountries() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.get(
        Uri.parse('https://passport.bilibili.com/web/generic/country/list'),
        headers: NetworkConfig.biliHeaders,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 0) {
          final commonCountries = List<Map<String, dynamic>>.from(
            data['data']['common'].map(
              (item) => {
                'id': item['id'], // 数据库ID，用于提交到API
                'cname': item['cname'],
                'country_id': item['country_id'], // 国际冠字码，用于显示
              },
            ),
          );

          final otherCountries = List<Map<String, dynamic>>.from(
            data['data']['others'].map(
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
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('加载国家列表失败: $e')));
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 获取验证码
  Future<void> _getCaptcha() async {
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
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('人机验证失败: ${message.toString()}')),
              );
            },
          ),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('获取验证码失败')));
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('获取验证码失败: $e')));
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 发送短信验证码
  Future<void> _sendSmsCode(Map<String, String> validateResult) async {
    if (_phoneNumber.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('请输入手机号')));
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
        'challenge': validateResult['geetest_challenge'],
        'validate': validateResult['geetest_validate'] ?? '',
        'seccode': validateResult['geetest_seccode'] ?? '',
      };
      debugPrint(requester.toString());
      final header = {
        ...NetworkConfig.biliHeaders,
        'Content-Type': 'application/x-www-form-urlencoded',
        'Host': 'passport.bilibili.com',
      };
      debugPrint(header.toString());
      final response = await http.post(
        Uri.parse(
          'https://passport.bilibili.com/x/passport-login/web/sms/send',
        ),
        headers: header,
        body: requester,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 0) {
          setState(() {
            _isCaptchaSent = true;
            _captchaKey = data['data']['captcha_key'];
          });

          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('短信验证码已发送')));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('发送验证码失败: ${data['message']}(${data['code']})'),
            ),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('发送验证码失败: $e')));
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 短信登录
  Future<void> _smsLogin() async {
    if (_phoneNumber.isEmpty || _captcha.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('请输入手机号和验证码')));
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse(
          'https://passport.bilibili.com/x/passport-login/web/login/sms',
        ),
        headers: {
          ...NetworkConfig.biliHeaders,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'cid': _countryId, // 使用数据库ID而不是国际冠字码
          'tel': _phoneNumber,
          'code': _captcha,
          'source': 'main-fe-header',
          'captcha_key': _captchaKey,
          'go_url': "https://www.bilibili.com/",
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 0) {
          final cookies = NetworkConfig.parseSetCookieHeaders(
            response.headers['set-cookie'] ?? '',
          );
          if (cookies.isNotEmpty) {
            NetworkConfig.updateCookies(cookies);
          }

          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('登录成功')));

          ShellPageManager.instance.pop(); // 返回上一页
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('登录失败: ${data['message']}')));
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('登录失败: $e')));
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 获取公钥和盐
  Future<Map<String, dynamic>?> _getPublicKey() async {
    try {
      final response = await http.get(
        Uri.parse('https://passport.bilibili.com/x/passport-login/web/key'),
        headers: NetworkConfig.biliHeaders,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 0) {
          return {'hash': data['data']['hash'], 'key': data['data']['key']};
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('获取公钥失败: $e')));
    }
    return null;
  }

  // 密码登录
  Future<void> _passwordLogin() async {
    if (_phoneNumber.isEmpty || _password.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('请输入账号和密码')));
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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('人机验证失败: ${message.toString()}')),
            );
          },
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('登录失败: $e')));
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 执行密码登录
  Future<void> _doPasswordLogin(Map<String, String> validateResult) async {
    try {
      // 2. 获取公钥和盐
      final keyInfo = await _getPublicKey();
      if (keyInfo == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // 3. 加密密码（简化处理，实际应使用RSA加密）
      final hashedPassword = sha256
          .convert(utf8.encode(keyInfo['hash'] + _password))
          .toString();

      // 4. 登录
      final response = await http.post(
        Uri.parse('https://passport.bilibili.com/x/passport-login/web/login'),
        headers: {
          ...NetworkConfig.biliHeaders,
          'Content-Type': 'application/x-www-form-urlencoded',
          'Host': 'passport.bilibili.com',
        },
        body: {
          'username': _phoneNumber,
          'password': hashedPassword,
          'keep': '0',
          'token': _captchaToken,
          'challenge': validateResult['geetest_challenge'],
          'validate': validateResult['geetest_validate'] ?? '',
          'seccode': validateResult['geetest_seccode'] ?? '',
          'source': 'main-fe-header',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 0) {
          final cookies = NetworkConfig.parseSetCookieHeaders(
            response.headers['set-cookie'] ?? '',
          );
          if (cookies.isNotEmpty) {
            NetworkConfig.updateCookies(cookies);
          }

          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('登录成功')));

          ShellPageManager.instance.pop(); // 返回上一页
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('登录失败: ${data['message']}')));
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('登录失败: $e')));
    } finally {
      setState(() {
        _isLoading = false;
      });
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('登录成功')));
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
