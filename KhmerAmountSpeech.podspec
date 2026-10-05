Pod::Spec.new do |s|
  s.name             = 'KhmerAmountSpeech'
  s.version          = '1.0.0'
  s.summary          = 'Offline Khmer and English speech for money amounts, composed from pre-recorded audio.'
  s.description      = <<-DESC
    Speaks KHR/USD amounts such as "មួយលានពីរសែនប្រាំម៉ឺនរៀល" entirely on device. Amounts are
    converted to Khmer (formal reading) or English words and played back by joining a small set of
    bundled, pre-recorded clips (digits, place-value units, round-amount compounds, currencies and
    phrases such as ទទួលប្រាក់ចំនួន) with sample-accurate gaps. No TTS service is called and no
    amount ever leaves the device.
  DESC

  s.homepage         = 'https://github.com/your-org/KhmerAmountSpeech'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'many.pichr' => 'many.pichr168@gmail.com' }
  s.source           = { :git => 'https://github.com/your-org/KhmerAmountSpeech.git', :tag => s.version.to_s }

  s.ios.deployment_target = '13.0'
  s.swift_versions   = ['5.9']
  s.frameworks       = 'AVFoundation'

  s.source_files     = 'Sources/KhmerAmountSpeech/**/*.swift'
  # A folder (not a glob) keeps the audio/<lang>/<type>/<value>.mp3 layout inside the bundle.
  s.resource_bundles = { 'KhmerAmountSpeech' => ['Sources/KhmerAmountSpeech/Resources/audio'] }

  s.test_spec 'Tests' do |t|
    t.source_files = 'Tests/KhmerAmountSpeechTests/**/*.swift'
  end
end
